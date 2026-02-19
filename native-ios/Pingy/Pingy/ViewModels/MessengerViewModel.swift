import Foundation
import UIKit

@MainActor
final class MessengerViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationID: String?
    @Published var messagesByConversation: [String: [Message]] = [:]
    @Published var typingByConversation: [String: String] = [:]
    @Published var onlineUserIDs = Set<String>()
    @Published var isLoadingConversations = false
    @Published var isLoadingMessages = false
    @Published var searchQuery = ""
    @Published var searchResults: [User] = []
    @Published var blockedUsers: [User] = []
    @Published var currentUserSettings: User?
    @Published var activeError: String?
    @Published var isSendingMessage = false
    @Published var isUploadingAvatar = false
    @Published var isSavingProfile = false
    @Published var profileSaveToken = UUID()
    @Published var pendingReplyMessage: Message?
    @Published var isSettingsPresented = false
    @Published var isProfilePresented = false
    @Published var isChatSettingsPresented = false

    private let authService: AuthService
    private let conversationService: ConversationService
    private let messageService: MessageService
    private let settingsService: SettingsService
    private let socketManager: SocketIOWebSocketManager
    private let cryptoService: E2EECryptoService
    private var notificationObserver: NSObjectProtocol?
    private var isSocketBound = false

    init(
        authService: AuthService,
        conversationService: ConversationService,
        messageService: MessageService,
        settingsService: SettingsService,
        socketManager: SocketIOWebSocketManager,
        cryptoService: E2EECryptoService
    ) {
        self.authService = authService
        self.conversationService = conversationService
        self.messageService = messageService
        self.settingsService = settingsService
        self.socketManager = socketManager
        self.cryptoService = cryptoService

        notificationObserver = NotificationCenter.default.addObserver(
            forName: .pingyOpenConversationFromPush,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let conversationID = note.userInfo?["conversationId"] as? String {
                Task {
                    await self.selectConversation(conversationID)
                }
            }
        }
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    var selectedConversation: Conversation? {
        conversations.first(where: { $0.conversationId == selectedConversationID })
    }

    var cryptoServiceProxy: E2EECryptoService {
        cryptoService
    }

    var currentUserID: String? {
        authService.sessionStore.currentUser?.id
    }

    var activeMessages: [Message] {
        guard let selectedConversationID else { return [] }
        return messagesByConversation[selectedConversationID] ?? []
    }

    func bindSocket() {
        guard !isSocketBound else {
            socketManager.connectIfNeeded()
            return
        }

        isSocketBound = true
        socketManager.onEvent = { [weak self] event in
            guard let self else { return }
            self.handleSocketEvent(event)
        }
        socketManager.connectIfNeeded()
    }

    func disconnectSocket() {
        isSocketBound = false
        socketManager.onEvent = nil
        socketManager.disconnect()
    }

    func reloadAll() async {
        await loadConversations()
        await loadSettings()
    }

    func loadConversations() async {
        isLoadingConversations = true
        defer { isLoadingConversations = false }

        do {
            conversations = try await conversationService.listConversations()
        } catch {
            setError(from: error)
        }
    }

    func loadSettings() async {
        do {
            let settings = try await settingsService.getMySettings()
            currentUserSettings = settings.user
            blockedUsers = settings.blockedUsers
        } catch {
            setError(from: error)
        }
    }

    func selectConversation(_ conversationID: String?) async {
        if let current = selectedConversationID, current != conversationID {
            socketManager.leaveConversation(current)
        }

        selectedConversationID = conversationID
        pendingReplyMessage = nil

        guard let conversationID else {
            return
        }

        socketManager.joinConversation(conversationID)
        await loadMessages(conversationID: conversationID)
    }

    func loadMessages(conversationID: String, force: Bool = false) async {
        if !force, messagesByConversation[conversationID] != nil {
            await markCurrentAsSeen()
            return
        }

        isLoadingMessages = true
        defer { isLoadingMessages = false }

        do {
            let messages = try await messageService.listMessages(conversationID: conversationID)
            messagesByConversation[conversationID] = messages.sorted(by: { $0.createdAt < $1.createdAt })
            await markCurrentAsSeen()
        } catch {
            setError(from: error)
        }
    }

    func searchUsers() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        do {
            searchResults = try await conversationService.searchUsers(query: query)
        } catch {
            setError(from: error)
        }
    }

    func openOrCreateConversation(with user: User) async {
        do {
            let conversation = try await conversationService.createDirectConversation(recipientID: user.id)
            if !conversations.contains(where: { $0.conversationId == conversation.conversationId }) {
                conversations.insert(conversation, at: 0)
            }
            searchResults = []
            searchQuery = ""
            await selectConversation(conversation.conversationId)
        } catch {
            setError(from: error)
        }
    }

    func sendText(_ text: String) async {
        guard let conversation = selectedConversation else { return }
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        guard let me = authService.sessionStore.currentUser else { return }

        isSendingMessage = true
        defer { isSendingMessage = false }

        do {
            let peerKey = try await resolvePeerPublicKey(for: conversation)
            let encrypted = try await cryptoService.encryptText(
                plaintext: plain,
                userID: me.id,
                peerUserID: conversation.participantId,
                peerPublicKeyJWK: peerKey
            )

            let clientID = "ios-\(UUID().uuidString)"
            let sent: Message

            if socketManager.isConnected {
                do {
                    sent = try await socketManager.sendEncryptedMessage(
                        conversationId: conversation.conversationId,
                        body: encrypted,
                        clientId: clientID,
                        replyToMessageId: pendingReplyMessage?.id
                    )
                } catch {
                    AppLogger.debug("Socket send failed, falling back to REST.")
                    sent = try await messageService.sendTextMessage(
                        conversationID: conversation.conversationId,
                        encryptedBody: encrypted,
                        clientID: clientID,
                        replyToMessageID: pendingReplyMessage?.id
                    )
                }
            } else {
                sent = try await messageService.sendTextMessage(
                    conversationID: conversation.conversationId,
                    encryptedBody: encrypted,
                    clientID: clientID,
                    replyToMessageID: pendingReplyMessage?.id
                )
            }

            upsertMessage(sent)
            pendingReplyMessage = nil
        } catch {
            setError(from: error)
        }
    }

    func sendMedia(
        data: Data,
        fileName: String,
        mimeType: String,
        type: MessageType,
        body: String? = nil
    ) async {
        guard let conversation = selectedConversation else { return }

        do {
            let message = try await messageService.sendMediaMessage(
                conversationID: conversation.conversationId,
                fileData: data,
                fileName: fileName,
                mimeType: mimeType,
                type: type,
                body: body,
                voiceDurationMs: nil,
                clientID: "ios-\(UUID().uuidString)",
                replyToMessageID: pendingReplyMessage?.id
            )
            upsertMessage(message)
            pendingReplyMessage = nil
        } catch {
            setError(from: error)
        }
    }

    func sendVoice(url: URL, durationMs: Int) async {
        guard let conversation = selectedConversation else { return }
        do {
            let data = try Data(contentsOf: url)
            let message = try await messageService.sendMediaMessage(
                conversationID: conversation.conversationId,
                fileData: data,
                fileName: "voice-\(UUID().uuidString).m4a",
                mimeType: "audio/mp4",
                type: .voice,
                body: nil,
                voiceDurationMs: durationMs,
                clientID: "ios-\(UUID().uuidString)",
                replyToMessageID: pendingReplyMessage?.id
            )
            upsertMessage(message)
            pendingReplyMessage = nil
        } catch {
            setError(from: error)
        }
    }

    func markCurrentAsSeen() async {
        guard let conversationID = selectedConversationID else { return }
        let unseenIDs = (messagesByConversation[conversationID] ?? [])
            .filter { $0.seenAt == nil && $0.senderId != authService.sessionStore.currentUser?.id }
            .map(\.id)

        guard !unseenIDs.isEmpty else { return }

        socketManager.sendSeen(conversationId: conversationID, messageIds: unseenIDs)
        do {
            try await messageService.markSeen(conversationID: conversationID, messageIDs: unseenIDs)
        } catch {
            AppLogger.error("markSeen failed: \(error.localizedDescription)")
        }
    }

    func sendTyping(_ isTyping: Bool) {
        guard let conversationID = selectedConversationID else { return }
        if isTyping {
            socketManager.sendTypingStart(conversationId: conversationID)
        } else {
            socketManager.sendTypingStop(conversationId: conversationID)
        }
    }

    func toggleReaction(messageID: String, emoji: String) async {
        do {
            let update = try await messageService.toggleReaction(messageID: messageID, emoji: emoji)
            applyReactionUpdate(update)
        } catch {
            setError(from: error)
        }
    }

    func setReplyTarget(_ message: Message?) {
        pendingReplyMessage = message
    }

    func deleteSelectedConversation(forEveryone: Bool) async {
        guard let conversationID = selectedConversationID else { return }
        do {
            try await conversationService.deleteConversation(
                conversationID: conversationID,
                scope: forEveryone ? "both" : "self"
            )
            conversations.removeAll { $0.conversationId == conversationID }
            messagesByConversation[conversationID] = []
            selectedConversationID = nil
        } catch {
            setError(from: error)
        }
    }

    func blockSelectedUser() async {
        guard let participantID = selectedConversation?.participantId else { return }
        do {
            blockedUsers = try await settingsService.blockUser(userID: participantID)
            await loadConversations()
        } catch {
            setError(from: error)
        }
    }

    func unblockUser(_ userID: String) async {
        do {
            blockedUsers = try await settingsService.unblockUser(userID: userID)
            await loadConversations()
        } catch {
            setError(from: error)
        }
    }

    @discardableResult
    func saveProfile(username: String, bio: String) async -> Bool {
        isSavingProfile = true
        defer { isSavingProfile = false }

        do {
            let updated = try await settingsService.updateProfile(username: username, bio: bio)
            currentUserSettings = updated
            if var me = authService.sessionStore.currentUser, me.id == updated.id {
                me.username = updated.username
                me.bio = updated.bio
                me.avatarUrl = updated.avatarUrl
                let tokens = AuthTokens(
                    accessToken: authService.sessionStore.accessToken ?? "",
                    refreshToken: authService.sessionStore.refreshToken ?? ""
                )
                authService.sessionStore.update(user: me, tokens: tokens)
            }
            profileSaveToken = UUID()
            return true
        } catch {
            setError(from: error)
            return false
        }
    }

    func savePrivacy(showOnline: Bool, readReceipts: Bool) async {
        do {
            currentUserSettings = try await settingsService.updatePrivacy(
                showOnlineStatus: showOnline,
                readReceiptsEnabled: readReceipts
            )
        } catch {
            setError(from: error)
        }
    }

    func saveChat(themeMode: ThemeMode, defaultWallpaperURL: String?) async {
        do {
            currentUserSettings = try await settingsService.updateChat(
                themeMode: themeMode,
                defaultWallpaperURL: defaultWallpaperURL
            )
        } catch {
            setError(from: error)
        }
    }

    @discardableResult
    func uploadAvatar(_ imageData: Data, fileName: String, mimeType: String) async -> Bool {
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            currentUserSettings = try await settingsService.uploadAvatar(
                imageData: imageData,
                filename: fileName,
                mimeType: mimeType
            )
            await loadConversations()
            profileSaveToken = UUID()
            return true
        } catch {
            setError(from: error, fallback: "Couldn't upload profile photo. Try JPG/PNG under 5 MB.")
            return false
        }
    }

    func uploadDefaultWallpaper(_ imageData: Data, fileName: String, mimeType: String) async {
        do {
            currentUserSettings = try await settingsService.uploadDefaultWallpaper(
                imageData: imageData,
                filename: fileName,
                mimeType: mimeType
            )
        } catch {
            setError(from: error)
        }
    }

    func uploadConversationWallpaper(
        imageData: Data,
        fileName: String,
        mimeType: String,
        blurIntensity: Int
    ) async {
        guard let conversationID = selectedConversationID else { return }
        do {
            let event = try await conversationService.uploadConversationWallpaper(
                conversationID: conversationID,
                imageData: imageData,
                fileName: fileName,
                mimeType: mimeType,
                blurIntensity: blurIntensity
            )
            applyConversationWallpaperEvent(event)
        } catch {
            setError(from: error)
        }
    }

    func resetConversationWallpaper() async {
        guard let conversationID = selectedConversationID else { return }
        do {
            try await conversationService.resetConversationWallpaper(conversationID: conversationID)
            applyConversationWallpaperEvent(
                ConversationWallpaperEvent(conversationId: conversationID, wallpaperUrl: nil, blurIntensity: 0)
            )
        } catch {
            setError(from: error)
        }
    }

    func deleteMyAccount() async {
        do {
            try await settingsService.deleteMyAccount()
            await authService.logout()
            disconnectSocket()
            conversations = []
            messagesByConversation = [:]
            selectedConversationID = nil
        } catch {
            setError(from: error)
        }
    }

    func logout() async {
        disconnectSocket()
        await authService.logout()
        conversations = []
        messagesByConversation = [:]
        selectedConversationID = nil
    }

    private func resolvePeerPublicKey(for conversation: Conversation) async throws -> PublicKeyJWK {
        if let key = conversation.participantPublicKeyJwk {
            return key
        }
        let fetched = try await settingsService.getPublicKey(for: conversation.participantId)
        if let index = conversations.firstIndex(where: { $0.conversationId == conversation.conversationId }) {
            conversations[index].participantPublicKeyJwk = fetched
        }
        return fetched
    }

    private func handleSocketEvent(_ event: SocketEvent) {
        switch event {
        case .messageNew(let message):
            upsertMessage(message)
        case .messageDelivered(let update):
            patchLifecycle(update, kind: .delivered)
        case .messageSeen(let update):
            patchLifecycle(update, kind: .seen)
        case .messageReaction(let update):
            applyReactionUpdate(update)
        case .typingStart(let value):
            typingByConversation[value.conversationId] = value.username ?? "Typing..."
        case .typingStop(let value):
            typingByConversation[value.conversationId] = nil
        case .presenceSnapshot(let snapshot):
            onlineUserIDs = Set(snapshot.onlineUserIds)
            refreshConversationPresence()
        case .presenceUpdate(let update):
            if update.isOnline {
                onlineUserIDs.insert(update.userId)
            } else {
                onlineUserIDs.remove(update.userId)
            }
            refreshConversationPresence()
            updateConversationLastSeen(userID: update.userId, lastSeen: update.lastSeen)
        case .profileUpdate(let profile):
            applyProfileUpdate(profile)
        case .conversationWallpaper(let event):
            applyConversationWallpaperEvent(event)
        }
    }

    private enum LifecycleKind {
        case delivered
        case seen
    }

    private func upsertMessage(_ message: Message) {
        var current = messagesByConversation[message.conversationId] ?? []
        if let index = current.firstIndex(where: { $0.id == message.id }) {
            current[index] = message
        } else {
            current.append(message)
            current.sort(by: { $0.createdAt < $1.createdAt })
        }
        messagesByConversation[message.conversationId] = current

        if let conversationIndex = conversations.firstIndex(where: { $0.conversationId == message.conversationId }) {
            conversations[conversationIndex].lastMessageId = message.id
            conversations[conversationIndex].lastMessageType = message.type.rawValue
            conversations[conversationIndex].lastMessageBody = message.body
            conversations[conversationIndex].lastMessageIsEncrypted = message.isEncrypted
            conversations[conversationIndex].lastMessageMediaName = message.mediaName
            conversations[conversationIndex].lastMessageCreatedAt = message.createdAt
            conversations[conversationIndex].lastMessageSenderId = message.senderId
            if selectedConversationID != message.conversationId,
               message.senderId != authService.sessionStore.currentUser?.id
            {
                conversations[conversationIndex].unreadCount += 1
            }
        }

        conversations.sort(by: { ($0.lastMessageCreatedAt ?? "") > ($1.lastMessageCreatedAt ?? "") })
    }

    private func patchLifecycle(_ update: MessageLifecycleUpdate, kind: LifecycleKind) {
        guard var messages = messagesByConversation[update.conversationId] else { return }
        guard let index = messages.firstIndex(where: { $0.id == update.id }) else { return }

        var message = messages[index]
        message.deliveredAt = update.deliveredAt ?? message.deliveredAt
        if kind == .seen {
            message.seenAt = update.seenAt ?? message.seenAt
        }
        messages[index] = message
        messagesByConversation[update.conversationId] = messages
    }

    private func applyReactionUpdate(_ update: ReactionUpdate) {
        guard var messages = messagesByConversation[update.conversationId] else { return }
        guard let index = messages.firstIndex(where: { $0.id == update.messageId }) else { return }
        var message = messages[index]
        message.reactions = update.reactions
        messages[index] = message
        messagesByConversation[update.conversationId] = messages
    }

    private func refreshConversationPresence() {
        for index in conversations.indices {
            let participantID = conversations[index].participantId
            conversations[index].participantIsOnline = onlineUserIDs.contains(participantID)
        }
    }

    private func updateConversationLastSeen(userID: String, lastSeen: String?) {
        for index in conversations.indices where conversations[index].participantId == userID {
            conversations[index].participantLastSeen = lastSeen
        }
    }

    private func applyProfileUpdate(_ profile: ProfileUpdateEvent) {
        for index in conversations.indices where conversations[index].participantId == profile.userId {
            conversations[index].participantUsername = profile.username
            conversations[index].participantAvatarUrl = profile.avatarUrl
        }
    }

    private func applyConversationWallpaperEvent(_ event: ConversationWallpaperEvent) {
        for index in conversations.indices where conversations[index].conversationId == event.conversationId {
            conversations[index].wallpaperUrl = event.wallpaperUrl
            conversations[index].blurIntensity = event.blurIntensity
        }
    }

    private func setError(from error: Error, fallback: String? = nil) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lowered = message.lowercased()

        if lowered.contains("internal server error") {
            activeError = fallback ?? "Server is temporarily busy. Please try again."
            return
        }

        if lowered.contains("decode") {
            activeError = "We couldn't sync latest data. Pull to refresh and retry."
            return
        }

        activeError = fallback ?? message
    }
}
