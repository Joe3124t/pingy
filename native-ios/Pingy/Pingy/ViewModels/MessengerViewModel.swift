import Combine
import Foundation
import Network
import SwiftUI
import UIKit

enum NetworkBannerState: Equatable {
    case hidden
    case waitingForInternet
    case connecting
    case updating
}

enum OutgoingMessageState: Equatable {
    case sending
    case sent
    case delivered
    case read
    case failed
}

enum TransientNoticeStyle: Equatable {
    case info
    case warning
    case error
    case success
}

struct TransientNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: TransientNoticeStyle
}

@MainActor
final class MessengerViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationID: String?
    @Published var messagesByConversation: [String: [Message]] = [:]
    @Published var typingByConversation: [String: String] = [:]
    @Published var recordingByConversation: [String: String] = [:]
    @Published var onlineUserIDs = Set<String>()
    @Published var isLoadingConversations = false
    @Published var isLoadingMessages = false
    @Published var searchQuery = ""
    @Published var searchResults: [User] = []
    @Published var contactSearchResults: [ContactSearchResult] = []
    @Published var contactSearchHint: String?
    @Published var isSyncingContacts = false
    @Published var blockedUsers: [User] = []
    @Published var currentUserSettings: User?
    @Published var activeError: String?
    @Published var pinnedConversationIDs = Set<String>()
    @Published var archivedConversationIDs = Set<String>()
    @Published var isSendingMessage = false
    @Published var isUploadingAvatar = false
    @Published var isSavingProfile = false
    @Published var profileSaveToken = UUID()
    @Published var pendingReplyMessage: Message?
    @Published var isSettingsPresented = false
    @Published var isProfilePresented = false
    @Published var isChatSettingsPresented = false
    @Published var isCompactChatDetailPresented = false
    @Published private(set) var networkBannerState: NetworkBannerState = .hidden
    @Published private(set) var isInternetReachable = true
    @Published private(set) var isSocketConnected = false
    @Published private(set) var isSocketConnecting = false
    @Published private(set) var mediaUploadProgressByClientID: [String: Double] = [:]
    @Published private(set) var failedMediaClientIDs = Set<String>()
    @Published private(set) var failedTextClientIDs = Set<String>()
    @Published private(set) var activeDurationTick = Date()
    @Published private(set) var decryptedMessageBodyByID: [String: String] = [:]
    @Published private(set) var transientNotice: TransientNotice?

    private let authService: AuthService
    private let conversationService: ConversationService
    private let messageService: MessageService
    private let settingsService: SettingsService
    private let contactSyncService: ContactSyncService
    private let socketManager: SocketIOWebSocketManager
    private let cryptoService: E2EECryptoService
    private let callSignalingService: CallSignalingService
    private let localCache = LocalDatabaseCache.shared
    private let userDefaults = UserDefaults.standard
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "pingy.network.monitor")
    private var notificationObserver: NSObjectProtocol?
    private var socketConnectionObserver: AnyCancellable?
    private var socketConnectingObserver: AnyCancellable?
    private var isSocketBound = false
    private var isSyncingAfterReconnect = false
    private var reconnectSyncRetryTask: Task<Void, Never>?
    private var mediaRetryTask: Task<Void, Never>?
    private var textRetryTask: Task<Void, Never>?
    private var transientNoticeTask: Task<Void, Never>?
    private var socketConnectingSince: Date?
    private var keyRefreshTasks: [String: Task<PublicKeyJWK, Error>] = [:]
    private var pendingTextQueue: [PendingTextMessage] = []
    private var inFlightTextClientIDs = Set<String>()
    private var pendingMediaQueue: [PendingMediaMessage] = []
    private var isProcessingTextQueue = false
    private var isProcessingMediaQueue = false
    private var openConversationTasks: [String: Task<Void, Never>] = [:]
    private var syncedContactMatches: [ContactSearchResult] = []
    private let conversationListStateStore = ConversationListStateStore.shared
    private var onlineSinceByUserID: [String: Date] = [:]
    private var activeDurationTimer: Timer?
    private var typingExpiryTasks: [String: Task<Void, Never>] = [:]
    private var recordingExpiryTasks: [String: Task<Void, Never>] = [:]

    private struct PendingTextMessage: Codable {
        let conversationId: String
        let participantId: String
        let plainText: String
        let replyToMessageId: String?
        let clientId: String
        let createdAtISO: String
        let retryAttempt: Int?
        let nextRetryAtISO: String?
    }

    private struct PendingMediaMessage: Codable {
        let conversationId: String
        let participantId: String
        let type: MessageType
        let fileName: String
        let mimeType: String
        let mediaSize: Int
        let body: String?
        let replyToMessageId: String?
        let clientId: String
        let createdAtISO: String
        let localMediaURL: String
    }

    private struct PendingQueueSnapshot: Codable {
        let text: [PendingTextMessage]
        let media: [PendingMediaMessage]
    }

    private struct CachedContactMatch: Codable {
        let user: User
        let contactName: String
    }

    private enum PendingQueueError: Error {
        case conversationUnavailable
        case mediaUnavailable
    }

    private enum CacheKeys {
        static func conversations(userID: String) -> String {
            "pingy.cache.conversations.\(userID)"
        }

        static func messages(userID: String) -> String {
            "pingy.cache.messages.\(userID)"
        }

        static func pendingQueue(userID: String) -> String {
            "pingy.cache.pendingQueue.\(userID)"
        }

        static func contactMatches(userID: String) -> String {
            "pingy.cache.contactMatches.\(userID)"
        }

        static func settings(userID: String) -> String {
            "pingy.cache.settings.\(userID)"
        }
    }

    init(
        authService: AuthService,
        conversationService: ConversationService,
        messageService: MessageService,
        settingsService: SettingsService,
        contactSyncService: ContactSyncService,
        socketManager: SocketIOWebSocketManager,
        cryptoService: E2EECryptoService,
        callSignalingService: CallSignalingService
    ) {
        self.authService = authService
        self.conversationService = conversationService
        self.messageService = messageService
        self.settingsService = settingsService
        self.contactSyncService = contactSyncService
        self.socketManager = socketManager
        self.cryptoService = cryptoService
        self.callSignalingService = callSignalingService
        self.callSignalingService.onRingingTimeout = { [weak self] session in
            self?.sendCallEnded(
                callId: session.id,
                conversationId: session.conversationId,
                participantID: session.participantId,
                status: .missed
            )
        }

        notificationObserver = NotificationCenter.default.addObserver(
            forName: .pingyOpenConversationFromPush,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let conversationID = note.userInfo?["conversationId"] as? String {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !self.conversations.contains(where: { $0.conversationId == conversationID }) {
                        await self.loadConversations()
                    }
                    await self.selectConversation(conversationID)
                }
            }
        }

        isSocketConnected = socketManager.isConnected
        isSocketConnecting = socketManager.isConnecting
        socketConnectionObserver = socketManager.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnected in
                guard let self else { return }
                self.handleSocketConnectionUpdate(isConnected: isConnected)
            }
        socketConnectingObserver = socketManager.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnecting in
                guard let self else { return }
                self.handleSocketConnectingUpdate(isConnecting: isConnecting)
            }

        startActiveDurationTimer()
        startNetworkMonitoring()
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
        socketConnectionObserver?.cancel()
        socketConnectingObserver?.cancel()
        reconnectSyncRetryTask?.cancel()
        mediaRetryTask?.cancel()
        textRetryTask?.cancel()
        activeDurationTimer?.invalidate()
        typingExpiryTasks.values.forEach { $0.cancel() }
        recordingExpiryTasks.values.forEach { $0.cancel() }
        networkMonitor.cancel()
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

    var totalUnreadCount: Int {
        conversations.reduce(0) { $0 + max(0, $1.unreadCount) }
    }

    func contactDisplayName(for conversation: Conversation) -> String {
        contactDisplayName(for: conversation.participantId, fallback: conversation.participantUsername)
    }

    func contactDisplayName(for participantId: String, fallback: String) -> String {
        let normalizedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackValue = normalizedFallback.isEmpty ? "Pingy User" : normalizedFallback
        return contactNameByUserId[participantId] ?? fallbackValue
    }

    func contactPhoneNumber(for participantId: String) -> String? {
        contactPhoneByUserId[participantId]
    }

    func messages(for conversationId: String) -> [Message] {
        messagesByConversation[conversationId] ?? []
    }

    func decryptedBody(for message: Message) -> String? {
        decryptedMessageBodyByID[message.id]
    }

    func mediaUploadProgress(for message: Message) -> Double? {
        guard let clientId = message.clientId else { return nil }
        return mediaUploadProgressByClientID[clientId]
    }

    func outgoingState(for message: Message) -> OutgoingMessageState? {
        guard message.senderId == currentUserID else { return nil }

        if let clientId = message.clientId {
            if failedTextClientIDs.contains(clientId) {
                return .failed
            }
            if inFlightTextClientIDs.contains(clientId) ||
                pendingTextQueue.contains(where: { $0.clientId == clientId }) ||
                pendingMediaQueue.contains(where: { $0.clientId == clientId })
            {
                return .sending
            }
        } else if message.id.hasPrefix("local-") {
            return .failed
        }

        if message.seenAt != nil {
            return .read
        }
        if message.deliveredAt != nil {
            return .delivered
        }
        return .sent
    }

    func canRetryTextMessage(for message: Message) -> Bool {
        guard let clientId = message.clientId else { return false }
        return failedTextClientIDs.contains(clientId)
    }

    func retryPendingTextMessage(for message: Message) {
        guard let clientId = message.clientId, !clientId.isEmpty else { return }
        guard let conversation = conversations.first(where: { $0.conversationId == message.conversationId }) else { return }

        if !pendingTextQueue.contains(where: { $0.clientId == clientId }) {
            let queued = PendingTextMessage(
                conversationId: message.conversationId,
                participantId: conversation.participantId,
                plainText: MessageBodyFormatter.previewText(from: message.body, fallback: "").trimmingCharacters(in: .whitespacesAndNewlines),
                replyToMessageId: normalizedReplyToMessageId(message.replyToMessageId),
                clientId: clientId,
                createdAtISO: message.createdAt,
                retryAttempt: 0,
                nextRetryAtISO: nil
            )
            if !queued.plainText.isEmpty {
                pendingTextQueue.insert(queued, at: 0)
            }
        }

        failedTextClientIDs.remove(clientId)
        activeError = nil
        persistPendingQueue()

        Task { [weak self] in
            await self?.processPendingTextQueue()
        }
    }

    func canRetryMediaUpload(for message: Message) -> Bool {
        guard let clientId = message.clientId else { return false }
        return failedMediaClientIDs.contains(clientId)
    }

    func presenceStatus(for conversation: Conversation) -> (text: String, highlighted: Bool) {
        if let recording = recordingByConversation[conversation.conversationId], !recording.isEmpty {
            return ("recording audio...", true)
        }

        if typingByConversation[conversation.conversationId] != nil {
            return ("typing...", true)
        }

        if conversation.participantIsOnline {
            if let since = onlineSinceByUserID[conversation.participantId] {
                let elapsed = max(0, Int(Date().timeIntervalSince(since)))
                return ("Active for \(formattedDuration(elapsed))", false)
            }
            return ("Online", false)
        }

        return (formatLastSeen(conversation.participantLastSeen), false)
    }

    func retryPendingMediaUpload(for message: Message) {
        guard let clientId = message.clientId else { return }
        guard let index = pendingMediaQueue.firstIndex(where: { $0.clientId == clientId }) else { return }

        let item = pendingMediaQueue.remove(at: index)
        pendingMediaQueue.insert(item, at: 0)
        persistPendingQueue()
        failedMediaClientIDs.remove(clientId)
        mediaUploadProgressByClientID[clientId] = 0.08

        Task { [weak self] in
            await self?.processPendingMediaQueue()
        }
    }

    func bindSocket() {
        guard !isSocketBound else {
            socketManager.connectIfNeeded()
            updateNetworkBannerState()
            return
        }

        isSocketBound = true
        socketManager.onEvent = { [weak self] event in
            guard let self else { return }
            self.handleSocketEvent(event)
        }
        socketManager.connectIfNeeded()
        updateNetworkBannerState()
    }

    func disconnectSocket() {
        isSocketBound = false
        socketManager.onEvent = nil
        socketManager.disconnect()
        isSocketConnected = false
        updateNetworkBannerState()
    }

    func reloadAll() async {
        await ensurePublicKeyPublished()
        await restoreCachedStateFromDatabase()
        restoreCachedState()
        scheduleEncryptedMessageDecryptionForCachedConversations()
        await loadConversationListState()
        await loadConversations(silent: true)
        await loadSettings(silent: true)
        await refreshContactSync(promptForPermission: false)
        if !pendingTextQueue.isEmpty {
            await processPendingTextQueue()
        }
        if !pendingMediaQueue.isEmpty {
            await processPendingMediaQueue()
        }
        updateNetworkBannerState()
    }

    private func scheduleEncryptedMessageDecryptionForCachedConversations() {
        for (_, messages) in messagesByConversation {
            for message in messages where message.isEncrypted && message.type == .text {
                scheduleEncryptedMessageDecryptionIfNeeded(message)
            }
        }
    }

    @discardableResult
    func loadConversations(silent: Bool = false) async -> Bool {
        isLoadingConversations = true
        defer { isLoadingConversations = false }

        do {
            conversations = try await conversationService.listConversations()
            for conversation in conversations where conversation.participantIsOnline {
                if onlineSinceByUserID[conversation.participantId] == nil {
                    onlineSinceByUserID[conversation.participantId] = Date()
                }
            }
            persistConversationsCache()
            return true
        } catch {
            if isTransientNetworkError(error) {
                AppLogger.debug("Skipping conversations refresh error while offline.")
                return false
            }
            if !silent {
                setError(from: error)
            } else {
                AppLogger.error("Silent conversations refresh failed: \(error.localizedDescription)")
            }
            return false
        }
    }

    func isConversationPinned(_ conversationID: String) -> Bool {
        pinnedConversationIDs.contains(conversationID)
    }

    func isConversationArchived(_ conversationID: String) -> Bool {
        archivedConversationIDs.contains(conversationID)
    }

    func togglePinConversation(_ conversationID: String) {
        if pinnedConversationIDs.contains(conversationID) {
            pinnedConversationIDs.remove(conversationID)
        } else {
            if pinnedConversationIDs.count >= 5 {
                activeError = "You can pin up to 5 chats."
                return
            }
            pinnedConversationIDs.insert(conversationID)
            archivedConversationIDs.remove(conversationID)
        }
        persistConversationListState()
    }

    func archiveConversation(_ conversationID: String) {
        archivedConversationIDs.insert(conversationID)
        pinnedConversationIDs.remove(conversationID)
        persistConversationListState()
    }

    func unarchiveConversation(_ conversationID: String) {
        archivedConversationIDs.remove(conversationID)
        persistConversationListState()
    }

    func toggleArchiveConversation(_ conversationID: String) {
        if archivedConversationIDs.contains(conversationID) {
            unarchiveConversation(conversationID)
        } else {
            archiveConversation(conversationID)
        }
    }

    func markConversationUnread(_ conversationID: String) {
        guard let index = conversations.firstIndex(where: { $0.conversationId == conversationID }) else { return }
        conversations[index].unreadCount = max(conversations[index].unreadCount, 1)
    }

    func markConversationRead(_ conversationID: String) {
        guard let index = conversations.firstIndex(where: { $0.conversationId == conversationID }) else { return }
        conversations[index].unreadCount = 0
    }

    @discardableResult
    func loadSettings(silent: Bool = false) async -> Bool {
        do {
            let settings = try await settingsService.getMySettings()
            currentUserSettings = settings.user
            blockedUsers = settings.blockedUsers
            persistSettingsCache()
            return true
        } catch {
            if isTransientNetworkError(error) {
                AppLogger.debug("Keeping cached settings while offline.")
                return false
            }
            if !silent {
                setError(from: error)
            } else {
                AppLogger.error("Silent settings refresh failed: \(error.localizedDescription)")
            }
            return false
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

    @discardableResult
    func loadMessages(
        conversationID: String,
        force: Bool = false,
        suppressNetworkAlert: Bool = false
    ) async -> Bool {
        if !force, messagesByConversation[conversationID] != nil {
            await markCurrentAsSeen()
            return true
        }

        isLoadingMessages = true
        defer { isLoadingMessages = false }

        do {
            let messages = try await messageService.listMessages(conversationID: conversationID)
            let sortedMessages = messages.sorted(by: { $0.createdAt < $1.createdAt })
            messagesByConversation[conversationID] = sortedMessages
            for message in sortedMessages where message.isEncrypted && message.type == .text {
                scheduleEncryptedMessageDecryptionIfNeeded(message)
            }
            persistMessagesCache()
            await markCurrentAsSeen()
            return true
        } catch {
            if suppressNetworkAlert {
                AppLogger.debug("Suppressing message refresh alert for \(conversationID): \(error.localizedDescription)")
                if messagesByConversation[conversationID] == nil {
                    messagesByConversation[conversationID] = []
                }
                return false
            }
            if isTransientNetworkError(error) || isLikelyOfflineError(error) {
                AppLogger.debug("Keeping cached messages for \(conversationID) due offline refresh.")
                if messagesByConversation[conversationID] == nil {
                    messagesByConversation[conversationID] = []
                }
                return false
            }
            setError(from: error)
            return false
        }
    }

    func searchUsers() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            contactSearchResults = []
            contactSearchHint = nil
            return
        }

        if syncedContactMatches.isEmpty, !isSyncingContacts {
            await refreshContactSync(promptForPermission: false)
        }

        if syncedContactMatches.isEmpty {
            do {
                let fallbackMatches = try await contactSyncService.searchRegisteredUsersByContactName(
                    query: query,
                    limit: 20
                )
                if !fallbackMatches.isEmpty {
                    syncedContactMatches = fallbackMatches
                    persistContactMatchesCache()
                }
            } catch let contactError as ContactSyncError {
                if contactSearchHint == nil {
                    switch contactError {
                    case .permissionDenied, .permissionRequired:
                        contactSearchHint = "Enable contact access to find friends."
                    case .noContacts:
                        contactSearchHint = "No contacts found on this device."
                    case .routeUnavailable:
                        contactSearchHint = "Contact sync isn't available on this server yet."
                    }
                }
            } catch {
                if contactSearchHint == nil {
                    contactSearchHint = "Couldn't sync contacts right now. Please try again."
                }
            }
        }

        guard !syncedContactMatches.isEmpty else {
            let localFallback = localConversationSearchResults(query: query)
            contactSearchResults = localFallback
            searchResults = localFallback.map(\.user)
            contactSearchHint = localFallback.isEmpty ? contactSearchHint : nil
            return
        }

        let lowered = query.lowercased()
        let filtered = syncedContactMatches.filter { item in
            item.contactName.lowercased().contains(lowered) ||
                item.user.username.lowercased().contains(lowered)
        }

        contactSearchResults = filtered
        searchResults = filtered.map(\.user)

        if filtered.isEmpty {
            let localFallback = localConversationSearchResults(query: query)
            if localFallback.isEmpty {
                contactSearchHint = "No matching contacts found on Pingy."
            } else {
                contactSearchResults = localFallback
                searchResults = localFallback.map(\.user)
                contactSearchHint = nil
            }
        } else {
            contactSearchHint = nil
        }
    }

    func requestContactAccessAndSync() async {
        await refreshContactSync(promptForPermission: true)
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await searchUsers()
        }
    }

    func openOrCreateConversation(with user: User) async {
        if let existingTask = openConversationTasks[user.id] {
            await existingTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let conversation = try await self.conversationService.createDirectConversation(recipientID: user.id)
                if !self.conversations.contains(where: { $0.conversationId == conversation.conversationId }) {
                    self.conversations.insert(conversation, at: 0)
                }

                self.searchResults = []
                self.searchQuery = ""
                await self.selectConversation(conversation.conversationId)
            } catch {
                self.setError(from: error, fallback: "Couldn't open this chat right now. Try again.")
            }
        }

        openConversationTasks[user.id] = task
        await task.value
        openConversationTasks.removeValue(forKey: user.id)
    }

    func sendText(_ text: String) async {
        guard let conversation = selectedConversation else { return }
        guard let me = authService.sessionStore.currentUser else { return }
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        let queued = PendingTextMessage(
            conversationId: conversation.conversationId,
            participantId: conversation.participantId,
            plainText: plain,
            replyToMessageId: normalizedReplyToMessageId(pendingReplyMessage?.id),
            clientId: "ios-\(UUID().uuidString)",
            createdAtISO: ISO8601DateFormatter().string(from: Date()),
            retryAttempt: 0,
            nextRetryAtISO: nil
        )
        failedTextClientIDs.remove(queued.clientId)
        insertLocalPendingMessage(queued, conversation: conversation, sender: me)
        pendingReplyMessage = nil
        pendingTextQueue.append(queued)
        persistPendingQueue()
        await processPendingTextQueue()
    }

    func sendMedia(
        data: Data,
        fileName: String,
        mimeType: String,
        type: MessageType,
        body: String? = nil
    ) async {
        guard !data.isEmpty else {
            showTransientNotice("Selected media is empty and could not be sent.", style: .warning)
            return
        }
        guard let conversation = selectedConversation else { return }
        guard let me = authService.sessionStore.currentUser else { return }

        let clientId = "ios-\(UUID().uuidString)"
        let normalizedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let localMediaURL = await savePendingMediaFile(data: data, fileName: fileName, clientId: clientId) else {
            activeError = "Couldn't prepare media file. Please try another file."
            showTransientNotice(activeError ?? "Couldn't prepare media file.", style: .error)
            return
        }

        let queued = PendingMediaMessage(
            conversationId: conversation.conversationId,
            participantId: conversation.participantId,
            type: type,
            fileName: fileName,
            mimeType: mimeType,
            mediaSize: data.count,
            body: normalizedBody,
            replyToMessageId: normalizedReplyToMessageId(pendingReplyMessage?.id),
            clientId: clientId,
            createdAtISO: ISO8601DateFormatter().string(from: Date()),
            localMediaURL: localMediaURL
        )

        insertLocalPendingMediaMessage(queued, conversation: conversation, sender: me)
        pendingReplyMessage = nil
        pendingMediaQueue.append(queued)
        persistPendingQueue()
        mediaUploadProgressByClientID[clientId] = 0.05
        failedMediaClientIDs.remove(clientId)
        await processPendingMediaQueue()
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
                replyToMessageID: normalizedReplyToMessageId(pendingReplyMessage?.id)
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

    func sendRecordingIndicator(_ isRecording: Bool) {
        guard let conversationID = selectedConversationID else { return }
        if isRecording {
            socketManager.sendRecordingStart(conversationId: conversationID)
        } else {
            socketManager.sendRecordingStop(conversationId: conversationID)
        }
    }

    func sendCallInvite(callId: String, conversationId: String, participantID: String) {
        socketManager.sendCallInvite(
            callId: callId,
            conversationId: conversationId,
            toUserId: participantID
        )
    }

    func sendCallDeclined(callId: String, conversationId: String, participantID: String) {
        socketManager.sendCallDecline(
            callId: callId,
            conversationId: conversationId,
            toUserId: participantID
        )
    }

    func sendCallAccepted(callId: String, conversationId: String, participantID: String) {
        socketManager.sendCallAccept(
            callId: callId,
            conversationId: conversationId,
            toUserId: participantID
        )
    }

    func sendCallEnded(callId: String, conversationId: String, participantID: String, status: CallSignalStatus) {
        socketManager.sendCallEnd(
            callId: callId,
            conversationId: conversationId,
            toUserId: participantID,
            status: status
        )
    }

    func startCall(from conversation: Conversation) {
        let profile = CallSignalingService.CallParticipantProfile(
            conversationId: conversation.conversationId,
            participantId: conversation.participantId,
            displayName: contactDisplayName(for: conversation),
            avatarURL: conversation.participantAvatarUrl
        )
        let callId = UUID().uuidString
        callSignalingService.beginOutgoingCall(profile: profile, callId: callId)
        sendCallInvite(
            callId: callId,
            conversationId: conversation.conversationId,
            participantID: conversation.participantId
        )
    }

    func acceptActiveCall() {
        guard let session = callSignalingService.activeSession else { return }
        callSignalingService.acceptCurrentCall()
        sendCallAccepted(
            callId: session.id,
            conversationId: session.conversationId,
            participantID: session.participantId
        )
    }

    func declineActiveCall() {
        guard let session = callSignalingService.activeSession else { return }
        callSignalingService.declineCurrentCall()
        sendCallDeclined(
            callId: session.id,
            conversationId: session.conversationId,
            participantID: session.participantId
        )
    }

    func endActiveCall() {
        guard let session = callSignalingService.activeSession else { return }
        let status: CallSignalStatus = session.startedAt == nil ? .missed : .ended
        callSignalingService.endCurrentCall(status: status)
        sendCallEnded(
            callId: session.id,
            conversationId: session.conversationId,
            participantID: session.participantId,
            status: status
        )
    }

    func toggleCallMute() {
        callSignalingService.toggleMute()
    }

    func toggleCallSpeaker() {
        callSignalingService.toggleSpeaker()
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

    func deleteMessageLocally(messageID: String, conversationID: String) {
        guard var messages = messagesByConversation[conversationID] else { return }
        messages.removeAll { $0.id == messageID }
        messagesByConversation[conversationID] = messages
        decryptedMessageBodyByID.removeValue(forKey: messageID)
        persistMessagesCache()

        guard let conversationIndex = conversations.firstIndex(where: { $0.conversationId == conversationID }) else {
            return
        }

        let latest = messages.max(by: { $0.createdAt < $1.createdAt })
        conversations[conversationIndex].lastMessageId = latest?.id
        conversations[conversationIndex].lastMessageType = latest?.type.rawValue
        conversations[conversationIndex].lastMessageBody = latest?.body
        conversations[conversationIndex].lastMessageIsEncrypted = latest?.isEncrypted
        conversations[conversationIndex].lastMessageMediaName = latest?.mediaName
        conversations[conversationIndex].lastMessageCreatedAt = latest?.createdAt
        conversations[conversationIndex].lastMessageSenderId = latest?.senderId
        persistConversationsCache()
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
            pinnedConversationIDs.remove(conversationID)
            archivedConversationIDs.remove(conversationID)
            persistConversationListState()
            persistConversationsCache()
            persistMessagesCache()
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
            persistSettingsCache()
            profileSaveToken = UUID()
            return true
        } catch {
            setError(from: error)
            return false
        }
    }

    @discardableResult
    func changePhoneNumber(
        newPhoneNumber: String,
        currentPassword: String,
        totpCode: String?,
        recoveryCode: String?
    ) async -> Bool {
        let normalizedPhone = newPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTotp = totpCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRecovery = recoveryCode?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedPhone.isEmpty else {
            activeError = "Enter a new phone number."
            return false
        }

        guard !normalizedPassword.isEmpty else {
            activeError = "Enter your current password."
            return false
        }

        do {
            let response = try await settingsService.changePhoneNumber(
                newPhoneNumber: normalizedPhone,
                currentPassword: normalizedPassword,
                totpCode: normalizedTotp,
                recoveryCode: normalizedRecovery
            )
            currentUserSettings = response.user
            if let accessToken = authService.sessionStore.accessToken,
               let refreshToken = authService.sessionStore.refreshToken
            {
                authService.sessionStore.update(
                    user: response.user,
                    tokens: AuthTokens(accessToken: accessToken, refreshToken: refreshToken)
                )
            }
            persistSettingsCache()
            activeError = nil
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
            persistSettingsCache()
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
            persistSettingsCache()
        } catch {
            setError(from: error)
        }
    }

    @discardableResult
    func uploadAvatar(_ imageData: Data, fileName: String, mimeType: String) async -> Bool {
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            let updatedUser = try await settingsService.uploadAvatar(
                imageData: imageData,
                filename: fileName,
                mimeType: mimeType
            )
            currentUserSettings = updatedUser
            if var me = authService.sessionStore.currentUser, me.id == updatedUser.id {
                me.avatarUrl = updatedUser.avatarUrl
                me.username = updatedUser.username
                me.bio = updatedUser.bio
                let tokens = AuthTokens(
                    accessToken: authService.sessionStore.accessToken ?? "",
                    refreshToken: authService.sessionStore.refreshToken ?? ""
                )
                authService.sessionStore.update(user: me, tokens: tokens)
            }
            persistSettingsCache()
            await loadConversations()
            profileSaveToken = UUID()
            showTransientNotice("Profile photo updated.", style: .success)
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
            setError(from: error, fallback: "Couldn't update chat wallpaper on this device.")
        }
    }

    func updateConversationWallpaperBlur(_ blurIntensity: Int) async {
        guard let conversationID = selectedConversationID else { return }
        guard let conversation = conversations.first(where: { $0.conversationId == conversationID }) else { return }
        guard let wallpaperURL = conversation.wallpaperUrl, !wallpaperURL.isEmpty else {
            applyConversationWallpaperEvent(
                ConversationWallpaperEvent(
                    conversationId: conversationID,
                    wallpaperUrl: nil,
                    blurIntensity: 0
                )
            )
            return
        }

        do {
            let event = try await conversationService.updateConversationWallpaper(
                conversationID: conversationID,
                wallpaperURL: wallpaperURL,
                blurIntensity: max(0, min(20, blurIntensity))
            )
            applyConversationWallpaperEvent(event)
        } catch {
            setError(from: error, fallback: "Couldn't update wallpaper blur.")
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
            setError(from: error, fallback: "Couldn't reset chat wallpaper.")
        }
    }

    func deleteMyAccount() async {
        do {
            let userID = currentUserID
            try await settingsService.deleteMyAccount()
            await authService.logout()
            if let userID {
                await conversationListStateStore.clear(for: userID)
                clearCachedState(for: userID)
            }
            disconnectSocket()
            conversations = []
            messagesByConversation = [:]
            decryptedMessageBodyByID = [:]
            pendingTextQueue = []
            inFlightTextClientIDs = []
            pendingMediaQueue = []
            mediaRetryTask?.cancel()
            textRetryTask?.cancel()
            mediaUploadProgressByClientID = [:]
            failedMediaClientIDs = []
            failedTextClientIDs = []
            pinnedConversationIDs = []
            archivedConversationIDs = []
            onlineSinceByUserID = [:]
            typingByConversation = [:]
            recordingByConversation = [:]
            typingExpiryTasks.values.forEach { $0.cancel() }
            recordingExpiryTasks.values.forEach { $0.cancel() }
            typingExpiryTasks = [:]
            recordingExpiryTasks = [:]
            callSignalingService.dismissCallUI()
            selectedConversationID = nil
        } catch {
            setError(from: error)
        }
    }

    func logout() async {
        let userID = currentUserID
        disconnectSocket()
        await authService.logout()
        if let userID {
            await conversationListStateStore.clear(for: userID)
            clearCachedState(for: userID)
        }
        conversations = []
        messagesByConversation = [:]
        decryptedMessageBodyByID = [:]
        pendingTextQueue = []
        inFlightTextClientIDs = []
        pendingMediaQueue = []
        mediaRetryTask?.cancel()
        textRetryTask?.cancel()
        mediaUploadProgressByClientID = [:]
        failedMediaClientIDs = []
        failedTextClientIDs = []
        pinnedConversationIDs = []
        archivedConversationIDs = []
        onlineSinceByUserID = [:]
        typingByConversation = [:]
        recordingByConversation = [:]
        typingExpiryTasks.values.forEach { $0.cancel() }
        recordingExpiryTasks.values.forEach { $0.cancel() }
        typingExpiryTasks = [:]
        recordingExpiryTasks = [:]
        callSignalingService.dismissCallUI()
        selectedConversationID = nil
    }

    func resolvePeerPublicKey(
        conversationID: String,
        participantID: String,
        forceRefresh: Bool = false
    ) async throws -> PublicKeyJWK {
        if !forceRefresh,
           let cached = conversations.first(where: { $0.conversationId == conversationID })?.participantPublicKeyJwk
        {
            return cached
        }

        if let inflight = keyRefreshTasks[participantID] {
            return try await inflight.value
        }

        let refreshTask = Task { [settingsService] in
            try await settingsService.getPublicKey(for: participantID)
        }
        keyRefreshTasks[participantID] = refreshTask
        defer { keyRefreshTasks[participantID] = nil }

        let fetched = try await refreshTask.value
        if let index = conversations.firstIndex(where: { $0.conversationId == conversationID }) {
            conversations[index].participantPublicKeyJwk = fetched
        }
        return fetched
    }

    private func processPendingTextQueue() async {
        guard !isProcessingTextQueue else { return }
        guard authService.sessionStore.currentUser != nil else {
            pendingTextQueue.removeAll()
            persistPendingQueue()
            return
        }
        guard isInternetReachable else {
            updateNetworkBannerState()
            return
        }

        isProcessingTextQueue = true
        isSendingMessage = true
        textRetryTask?.cancel()
        textRetryTask = nil
        defer {
            isProcessingTextQueue = false
            isSendingMessage = false
        }

        while !pendingTextQueue.isEmpty {
            let rawItem = pendingTextQueue.removeFirst()
            let item = normalizedPendingTextMessage(rawItem)
            let now = Date()

            if let nextRetryDate = parseISO8601(item.nextRetryAtISO), nextRetryDate > now {
                pendingTextQueue.insert(item, at: 0)
                persistPendingQueue()
                scheduleTextQueueRetry(at: nextRetryDate)
                break
            }

            inFlightTextClientIDs.insert(item.clientId)
            persistPendingQueue()
            do {
                let sent = try await sendPendingTextMessage(item)
                inFlightTextClientIDs.remove(item.clientId)
                failedTextClientIDs.remove(item.clientId)
                upsertMessage(sent)
            } catch {
                inFlightTextClientIDs.remove(item.clientId)
                if isQueueItemDiscardable(error: error) {
                    AppLogger.debug("Dropping stale queued message \(item.clientId) due unavailable conversation.")
                    removeLocalPendingMessage(clientId: item.clientId, conversationID: item.conversationId)
                    failedTextClientIDs.remove(item.clientId)
                    continue
                }

                if shouldDropQueueItem(after: error) {
                    AppLogger.debug("Marking non-retriable queued message as failed \(item.clientId).")
                    failedTextClientIDs.insert(item.clientId)
                    continue
                }

                let nextAttempt = max(0, item.retryAttempt ?? 0) + 1
                let retryDelaySeconds = min(pow(2.0, Double(nextAttempt)), 30.0)
                let retryAt = Date().addingTimeInterval(retryDelaySeconds)
                let retriableItem = PendingTextMessage(
                    conversationId: item.conversationId,
                    participantId: item.participantId,
                    plainText: item.plainText,
                    replyToMessageId: item.replyToMessageId,
                    clientId: item.clientId,
                    createdAtISO: item.createdAtISO,
                    retryAttempt: nextAttempt,
                    nextRetryAtISO: ISO8601DateFormatter().string(from: retryAt)
                )

                pendingTextQueue.insert(retriableItem, at: 0)
                persistPendingQueue()
                if shouldAutoRetryQueue(after: error) {
                    AppLogger.debug("Keeping message queued until network is back: \(item.clientId)")
                    scheduleTextQueueRetry(at: retryAt)
                } else {
                    failedTextClientIDs.insert(item.clientId)
                }
                break
            }
        }

        if pendingTextQueue.isEmpty {
            persistPendingQueue()
        }
    }

    private func processPendingMediaQueue() async {
        guard !isProcessingMediaQueue else { return }
        guard authService.sessionStore.currentUser != nil else {
            pendingMediaQueue.removeAll()
            mediaUploadProgressByClientID.removeAll()
            failedMediaClientIDs.removeAll()
            persistPendingQueue()
            return
        }
        guard isInternetReachable else { return }

        isProcessingMediaQueue = true
        defer { isProcessingMediaQueue = false }

        while !pendingMediaQueue.isEmpty {
            let item = pendingMediaQueue[0]
            mediaUploadProgressByClientID[item.clientId] = max(mediaUploadProgressByClientID[item.clientId] ?? 0.05, 0.14)

            do {
                let sent = try await sendPendingMediaMessage(item)
                pendingMediaQueue.removeFirst()
                persistPendingQueue()
                mediaUploadProgressByClientID[item.clientId] = nil
                failedMediaClientIDs.remove(item.clientId)
                await primeMediaCache(fromLocalPath: item.localMediaURL, sentMessage: sent)
                cleanupPendingMediaFile(path: item.localMediaURL)
                upsertMessage(sent)
            } catch {
                if isQueueItemDiscardable(error: error) || shouldDropQueueItem(after: error) {
                    pendingMediaQueue.removeFirst()
                    persistPendingQueue()
                    mediaUploadProgressByClientID[item.clientId] = nil
                    failedMediaClientIDs.remove(item.clientId)
                    cleanupPendingMediaFile(path: item.localMediaURL)
                    removeLocalPendingMessage(clientId: item.clientId, conversationID: item.conversationId)
                    setError(from: error, fallback: "Couldn't send one media item. It was removed from queue.")
                    continue
                }

                if shouldAutoRetryMediaUpload(after: error) {
                    mediaUploadProgressByClientID[item.clientId] = 0.05
                    persistPendingQueue()
                    scheduleMediaQueueRetry(after: 2_500_000_000)
                    break
                }

                failedMediaClientIDs.insert(item.clientId)
                mediaUploadProgressByClientID[item.clientId] = nil
                setError(from: error, fallback: "Couldn't send media right now. Tap retry.")
                persistPendingQueue()
                break
            }
        }
    }

    private func scheduleMediaQueueRetry(after nanoseconds: UInt64) {
        mediaRetryTask?.cancel()
        mediaRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.processPendingMediaQueue()
        }
    }

    private func scheduleTextQueueRetry(at date: Date) {
        textRetryTask?.cancel()
        let delay = max(0.2, date.timeIntervalSinceNow)
        textRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.processPendingTextQueue()
        }
    }

    private func parseISO8601(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func sendPendingMediaMessage(_ item: PendingMediaMessage) async throws -> Message {
        guard authService.sessionStore.currentUser != nil else {
            throw APIError.unauthorized
        }

        guard conversations.contains(where: { $0.conversationId == item.conversationId }) else {
            throw PendingQueueError.conversationUnavailable
        }

        guard let fileData = await loadPendingMediaData(path: item.localMediaURL) else {
            throw PendingQueueError.mediaUnavailable
        }

        return try await messageService.sendMediaMessage(
            conversationID: item.conversationId,
            fileData: fileData,
            fileName: item.fileName,
            mimeType: item.mimeType,
            type: item.type,
            body: item.body,
            voiceDurationMs: nil,
            clientID: item.clientId,
            replyToMessageID: normalizedReplyToMessageId(item.replyToMessageId)
        )
    }

    private func sendPendingTextMessage(_ item: PendingTextMessage) async throws -> Message {
        guard authService.sessionStore.currentUser != nil else {
            throw APIError.unauthorized
        }

        guard let conversation = conversations.first(where: { $0.conversationId == item.conversationId }) else {
            throw PendingQueueError.conversationUnavailable
        }

        return try await deliverPendingTextMessage(item, conversation: conversation)
    }

    private func deliverPendingTextMessage(
        _ item: PendingTextMessage,
        conversation: Conversation
    ) async throws -> Message {
        do {
            return try await messageService.sendTextMessage(
                conversationID: conversation.conversationId,
                body: item.plainText,
                clientID: item.clientId,
                replyToMessageID: normalizedReplyToMessageId(item.replyToMessageId)
            )
        } catch {
            let restError = error

            // Keep socket as a compatibility fallback first when available.
            if socketManager.isConnected {
                AppLogger.debug("REST send failed for \(item.clientId), trying socket fallback.")
                do {
                    return try await socketManager.sendPlainTextMessage(
                        conversationId: item.conversationId,
                        body: item.plainText,
                        clientId: item.clientId,
                        replyToMessageId: item.replyToMessageId
                    )
                } catch {
                    if requiresEncryptedTextPayload(restError) || requiresEncryptedTextPayload(error) {
                        AppLogger.debug("Text requires encrypted payload, retrying with E2EE for \(item.clientId)")
                        return try await sendEncryptedTextMessage(item, conversation: conversation)
                    }
                    throw error
                }
            }

            if requiresEncryptedTextPayload(restError) {
                AppLogger.debug("Server requires encrypted text payload, retrying with E2EE body for \(item.clientId)")
                return try await sendEncryptedTextMessage(item, conversation: conversation)
            }

            throw restError
        }
    }

    private func requiresEncryptedTextPayload(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        guard case .server(_, let message) = apiError else { return false }
        let lowered = message.lowercased()
        return lowered.contains("encrypted text payload is required")
            || lowered.contains("encrypted payload is required")
            || lowered.contains("secure session")
    }

    private func sendEncryptedTextMessage(
        _ item: PendingTextMessage,
        conversation: Conversation
    ) async throws -> Message {
        guard let userID = currentUserID else {
            throw APIError.unauthorized
        }

        await ensurePublicKeyPublished()

        let peerPublicKey = try await resolvePeerPublicKey(
            conversationID: conversation.conversationId,
            participantID: conversation.participantId
        )

        let payload = try await cryptoService.encryptText(
            plaintext: item.plainText,
            userID: userID,
            peerUserID: conversation.participantId,
            peerPublicKeyJWK: peerPublicKey
        )

        return try await messageService.sendEncryptedTextMessage(
            conversationID: conversation.conversationId,
            payload: payload,
            clientID: item.clientId,
            replyToMessageID: normalizedReplyToMessageId(item.replyToMessageId)
        )
    }

    private func ensurePublicKeyPublished() async {
        guard let userID = currentUserID else { return }
        do {
            let key = try await cryptoService.ensureIdentity(for: userID)
            try await settingsService.upsertPublicKey(key)
        } catch {
            AppLogger.error("Failed to publish E2EE identity key: \(error.localizedDescription)")
        }
    }

    private func normalizedReplyToMessageId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UUID(uuidString: trimmed) == nil ? nil : trimmed
    }

    private func normalizedPendingTextMessage(_ item: PendingTextMessage) -> PendingTextMessage {
        PendingTextMessage(
            conversationId: item.conversationId,
            participantId: item.participantId,
            plainText: item.plainText,
            replyToMessageId: normalizedReplyToMessageId(item.replyToMessageId),
            clientId: item.clientId,
            createdAtISO: item.createdAtISO,
            retryAttempt: max(0, item.retryAttempt ?? 0),
            nextRetryAtISO: item.nextRetryAtISO
        )
    }

    private func isQueueItemDiscardable(error: Error) -> Bool {
        if let queueError = error as? PendingQueueError {
            return queueError == .mediaUnavailable
        }
        return false
    }

    private func removeLocalPendingMessage(clientId: String, conversationID: String) {
        guard var messages = messagesByConversation[conversationID] else { return }
        messages.removeAll { $0.clientId == clientId && $0.id.hasPrefix("local-") }
        messagesByConversation[conversationID] = messages
        persistMessagesCache()
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
            scheduleTypingExpiry(for: value.conversationId)
        case .typingStop(let value):
            typingByConversation[value.conversationId] = nil
            typingExpiryTasks[value.conversationId]?.cancel()
            typingExpiryTasks[value.conversationId] = nil
        case .recordingStart(let value):
            recordingByConversation[value.conversationId] = value.username ?? "Recording..."
            typingByConversation[value.conversationId] = nil
            scheduleRecordingExpiry(for: value.conversationId)
        case .recordingStop(let value):
            recordingByConversation[value.conversationId] = nil
            recordingExpiryTasks[value.conversationId]?.cancel()
            recordingExpiryTasks[value.conversationId] = nil
        case .presenceSnapshot(let snapshot):
            onlineUserIDs = Set(snapshot.onlineUserIds)
            onlineSinceByUserID = onlineUserIDs.reduce(into: [:]) { mapping, userID in
                mapping[userID] = onlineSinceByUserID[userID] ?? Date()
            }
            refreshConversationPresence()
        case .presenceUpdate(let update):
            if update.isOnline {
                onlineUserIDs.insert(update.userId)
                if onlineSinceByUserID[update.userId] == nil {
                    onlineSinceByUserID[update.userId] = Date()
                }
            } else {
                onlineUserIDs.remove(update.userId)
                onlineSinceByUserID.removeValue(forKey: update.userId)
            }
            refreshConversationPresence()
            updateConversationLastSeen(userID: update.userId, lastSeen: update.lastSeen)
        case .profileUpdate(let profile):
            applyProfileUpdate(profile)
        case .conversationWallpaper(let event):
            applyConversationWallpaperEvent(event)
        case .callSignal(let signal):
            guard let currentUserID else { return }
            callSignalingService.handleSignal(
                signal,
                currentUserID: currentUserID,
                profile: callProfile(for: signal, currentUserID: currentUserID)
            )
        }
    }

    private enum LifecycleKind {
        case delivered
        case seen
    }

    private func upsertMessage(_ message: Message) {
        if let clientId = message.clientId {
            failedTextClientIDs.remove(clientId)
            inFlightTextClientIDs.remove(clientId)
        }
        var current = messagesByConversation[message.conversationId] ?? []
        if let index = current.firstIndex(where: { $0.id == message.id }) {
            current[index] = message
        } else if let clientId = message.clientId,
                  let pendingIndex = current.firstIndex(where: { $0.clientId == clientId })
        {
            current[pendingIndex] = message
        } else {
            current.append(message)
            current.sort(by: { $0.createdAt < $1.createdAt })
        }
        messagesByConversation[message.conversationId] = current
        if !message.isEncrypted {
            decryptedMessageBodyByID.removeValue(forKey: message.id)
        } else {
            scheduleEncryptedMessageDecryptionIfNeeded(message)
        }
        persistMessagesCache()

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
        persistConversationsCache()
    }

    private func scheduleEncryptedMessageDecryptionIfNeeded(_ message: Message) {
        guard message.type == .text else { return }
        guard decryptedMessageBodyByID[message.id] == nil else { return }

        Task { [weak self] in
            await self?.attemptDecryptMessageForDisplay(message)
        }
    }

    private func attemptDecryptMessageForDisplay(_ message: Message) async {
        guard let payload = extractEncryptedPayload(from: message.body) else { return }
        guard let userID = currentUserID else { return }

        let peerUserID = message.senderId == userID ? message.recipientId : message.senderId

        let peerPublicKey: PublicKeyJWK
        if let conversation = conversations.first(where: { $0.conversationId == message.conversationId }),
           let key = conversation.participantPublicKeyJwk
        {
            peerPublicKey = key
        } else {
            guard let key = try? await resolvePeerPublicKey(
                conversationID: message.conversationId,
                participantID: peerUserID
            ) else {
                return
            }
            peerPublicKey = key
        }

        guard let plain = try? await cryptoService.decryptText(
            payload: payload,
            userID: userID,
            peerUserID: peerUserID,
            peerPublicKeyJWK: peerPublicKey
        ) else {
            return
        }

        let normalized = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        decryptedMessageBodyByID[message.id] = normalized
    }

    private func extractEncryptedPayload(from body: JSONValue?) -> EncryptedPayload? {
        guard let body else { return nil }

        let data: Data?
        switch body {
        case .object(let object):
            data = try? JSONEncoder().encode(object)
        case .string(let raw):
            data = raw.data(using: .utf8)
        default:
            data = nil
        }

        guard let data else { return nil }
        return try? JSONDecoder().decode(EncryptedPayload.self, from: data)
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
        persistMessagesCache()
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
            let isOnline = onlineUserIDs.contains(participantID)
            conversations[index].participantIsOnline = isOnline
            if isOnline {
                if onlineSinceByUserID[participantID] == nil {
                    onlineSinceByUserID[participantID] = Date()
                }
            } else {
                onlineSinceByUserID.removeValue(forKey: participantID)
            }
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

    private func callProfile(
        for signal: CallSignalEvent,
        currentUserID: String
    ) -> CallSignalingService.CallParticipantProfile? {
        let participantId = signal.fromUserId == currentUserID ? signal.toUserId : signal.fromUserId

        if let conversation = conversations.first(where: { $0.conversationId == signal.conversationId }) {
            return CallSignalingService.CallParticipantProfile(
                conversationId: conversation.conversationId,
                participantId: participantId,
                displayName: contactDisplayName(for: conversation),
                avatarURL: conversation.participantAvatarUrl
            )
        }

        if let conversation = conversations.first(where: { $0.participantId == participantId }) {
            return CallSignalingService.CallParticipantProfile(
                conversationId: conversation.conversationId,
                participantId: participantId,
                displayName: contactDisplayName(for: conversation),
                avatarURL: conversation.participantAvatarUrl
            )
        }

        return nil
    }

    private func loadConversationListState() async {
        guard let userID = currentUserID else {
            pinnedConversationIDs = []
            archivedConversationIDs = []
            return
        }

        let state = await conversationListStateStore.load(for: userID)
        pinnedConversationIDs = state.pinned
        archivedConversationIDs = state.archived
    }

    private func persistConversationListState() {
        guard let userID = currentUserID else { return }
        let pinned = pinnedConversationIDs
        let archived = archivedConversationIDs
        Task {
            await conversationListStateStore.save(
                pinned: pinned,
                archived: archived,
                for: userID
            )
        }
    }

    private func refreshContactSync(promptForPermission: Bool) async {
        isSyncingContacts = true
        defer { isSyncingContacts = false }

        do {
            let matches = try await contactSyncService.syncContacts(promptForPermission: promptForPermission)
            syncedContactMatches = matches
            persistContactMatchesCache()
            contactSearchResults = []
            if matches.isEmpty {
                contactSearchHint = "No contacts from your address book are on Pingy yet."
            } else {
                contactSearchHint = nil
            }
        } catch let contactError as ContactSyncError {
            if syncedContactMatches.isEmpty {
                syncedContactMatches = loadCachedContactMatches()
            }
            contactSearchResults = []
            switch contactError {
            case .permissionDenied, .permissionRequired:
                contactSearchHint = "Enable contact access to find friends."
            case .noContacts:
                contactSearchHint = "No contacts found on this device."
            case .routeUnavailable:
                contactSearchHint = "Contact sync isn't available on this server yet."
            }
        } catch {
            if syncedContactMatches.isEmpty {
                syncedContactMatches = loadCachedContactMatches()
            }
            contactSearchResults = []
            if syncedContactMatches.isEmpty {
                contactSearchHint = "Couldn't sync contacts right now. Please try again."
            } else {
                contactSearchHint = nil
            }
            AppLogger.error("Contact sync failed: \(error.localizedDescription)")
        }
    }

    private func startActiveDurationTimer() {
        activeDurationTimer?.invalidate()
        activeDurationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.activeDurationTick = Date()
            }
        }
    }

    private func formatLastSeen(_ iso: String?) -> String {
        guard let value = iso else {
            return "last seen recently"
        }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            return "last seen recently"
        }

        let output = DateFormatter()
        output.locale = .autoupdatingCurrent
        output.timeStyle = .short

        if Calendar.current.isDateInToday(date) {
            return "last seen today at \(output.string(from: date))"
        }

        if Calendar.current.isDateInYesterday(date) {
            return "last seen yesterday at \(output.string(from: date))"
        }

        output.dateStyle = .medium
        return "last seen \(output.string(from: date))"
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func scheduleTypingExpiry(for conversationID: String) {
        typingExpiryTasks[conversationID]?.cancel()
        typingExpiryTasks[conversationID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.typingByConversation[conversationID] = nil
                self?.typingExpiryTasks[conversationID] = nil
            }
        }
    }

    private func scheduleRecordingExpiry(for conversationID: String) {
        recordingExpiryTasks[conversationID]?.cancel()
        recordingExpiryTasks[conversationID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.recordingByConversation[conversationID] = nil
                self?.recordingExpiryTasks[conversationID] = nil
            }
        }
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                self.handleNetworkPathUpdate(isReachable: path.status == .satisfied)
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func handleNetworkPathUpdate(isReachable: Bool) {
        let wasReachable = isInternetReachable
        isInternetReachable = isReachable

        updateNetworkBannerState()

        guard authService.sessionStore.currentUser != nil else { return }

        if !isReachable {
            return
        }

        if !wasReachable {
            socketManager.connectIfNeeded()
        }

        Task { [weak self] in
            guard let self else { return }
            await self.startReconnectSyncIfNeeded()
        }
    }

    private func handleSocketConnectionUpdate(isConnected: Bool) {
        isSocketConnected = isConnected
        if isConnected {
            isSocketConnecting = false
            socketConnectingSince = nil
        }
        updateNetworkBannerState()
        if isConnected, isInternetReachable {
            Task { [weak self] in
                guard let self else { return }
                await self.startReconnectSyncIfNeeded()
            }
        }
    }

    private func handleSocketConnectingUpdate(isConnecting: Bool) {
        isSocketConnecting = isConnecting
        if isConnecting {
            socketConnectingSince = socketConnectingSince ?? Date()
        } else {
            socketConnectingSince = nil
        }
        updateNetworkBannerState()
    }

    private func updateNetworkBannerState() {
        let nextState: NetworkBannerState

        if !isInternetReachable {
            nextState = .waitingForInternet
        } else if isSocketBound,
                  authService.sessionStore.currentUser != nil,
                  !isSocketConnected,
                  isSocketConnecting
        {
            let connectingDuration = Date().timeIntervalSince(socketConnectingSince ?? Date())
            nextState = connectingDuration < 10 ? .connecting : .hidden
        } else if isSyncingAfterReconnect {
            nextState = .updating
        } else {
            nextState = .hidden
        }

        if nextState != networkBannerState {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                networkBannerState = nextState
            }
        }
    }

    private func startReconnectSyncIfNeeded() async {
        guard isInternetReachable else { return }
        guard authService.sessionStore.currentUser != nil else { return }
        guard isSocketConnected else {
            updateNetworkBannerState()
            return
        }
        guard !isSyncingAfterReconnect else { return }

        reconnectSyncRetryTask?.cancel()
        isSyncingAfterReconnect = true
        updateNetworkBannerState()

        let success = await performReconnectSync()
        if success {
            try? await Task.sleep(nanoseconds: 700_000_000)
            isSyncingAfterReconnect = false
            updateNetworkBannerState()
            return
        }

        isSyncingAfterReconnect = false
        updateNetworkBannerState()
        scheduleReconnectSyncRetry()
    }

    private func performReconnectSync() async -> Bool {
        let conversationsSynced = await loadConversations(silent: true)
        let settingsSynced = await loadSettings(silent: true)

        var messagesSynced = true
        if let selectedConversationID {
            messagesSynced = await loadMessages(
                conversationID: selectedConversationID,
                force: true,
                suppressNetworkAlert: true
            )
        }

        var queueSynced = true
        if !pendingTextQueue.isEmpty {
            await processPendingTextQueue()
            queueSynced = pendingTextQueue.isEmpty
        }
        if !pendingMediaQueue.isEmpty {
            await processPendingMediaQueue()
            queueSynced = queueSynced && pendingMediaQueue.isEmpty
        }

        return conversationsSynced
            && settingsSynced
            && messagesSynced
            && queueSynced
            && isInternetReachable
            && isSocketConnected
    }

    private func scheduleReconnectSyncRetry() {
        reconnectSyncRetryTask?.cancel()
        reconnectSyncRetryTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await self.startReconnectSyncIfNeeded()
        }
    }

    private func insertLocalPendingMessage(_ queued: PendingTextMessage, conversation: Conversation, sender: User) {
        let localMessage = Message(
            id: "local-\(queued.clientId)",
            conversationId: queued.conversationId,
            senderId: sender.id,
            senderUsername: sender.username,
            senderAvatarUrl: sender.avatarUrl,
            recipientId: conversation.participantId,
            replyToMessageId: queued.replyToMessageId,
            type: .text,
            body: .string(queued.plainText),
            isEncrypted: false,
            mediaUrl: nil,
            mediaName: nil,
            mediaMime: nil,
            mediaSize: nil,
            voiceDurationMs: nil,
            clientId: queued.clientId,
            createdAt: queued.createdAtISO,
            deliveredAt: nil,
            seenAt: nil,
            replyTo: pendingReplyMessage.map { source in
                MessageReply(
                    id: source.id,
                    senderId: source.senderId,
                    senderUsername: source.senderUsername,
                    type: source.type,
                    body: source.body,
                    isEncrypted: source.isEncrypted,
                    mediaName: source.mediaName,
                    createdAt: source.createdAt
                )
            },
            reactions: []
        )

        upsertMessage(localMessage)
    }

    private func insertLocalPendingMediaMessage(
        _ queued: PendingMediaMessage,
        conversation: Conversation,
        sender: User
    ) {
        let normalizedBody = queued.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyValue: JSONValue? = {
            guard let normalizedBody, !normalizedBody.isEmpty else { return nil }
            return .string(normalizedBody)
        }()

        let localMessage = Message(
            id: "local-\(queued.clientId)",
            conversationId: queued.conversationId,
            senderId: sender.id,
            senderUsername: sender.username,
            senderAvatarUrl: sender.avatarUrl,
            recipientId: conversation.participantId,
            replyToMessageId: queued.replyToMessageId,
            type: queued.type,
            body: bodyValue,
            isEncrypted: false,
            mediaUrl: queued.localMediaURL,
            mediaName: queued.fileName,
            mediaMime: queued.mimeType,
            mediaSize: queued.mediaSize,
            voiceDurationMs: nil,
            clientId: queued.clientId,
            createdAt: queued.createdAtISO,
            deliveredAt: nil,
            seenAt: nil,
            replyTo: pendingReplyMessage.map { source in
                MessageReply(
                    id: source.id,
                    senderId: source.senderId,
                    senderUsername: source.senderUsername,
                    type: source.type,
                    body: source.body,
                    isEncrypted: source.isEncrypted,
                    mediaName: source.mediaName,
                    createdAt: source.createdAt
                )
            },
            reactions: []
        )

        upsertMessage(localMessage)
    }

    private func savePendingMediaFile(data: Data, fileName: String, clientId: String) async -> String? {
        await Task.detached(priority: .utility) {
            let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            guard let baseURL else { return nil }

            let folder = baseURL.appendingPathComponent("pingy-pending-media", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                AppLogger.error("Failed to create pending media directory: \(error.localizedDescription)")
                return nil
            }

            let ext = URL(fileURLWithPath: fileName).pathExtension
            let resolvedExt = ext.isEmpty ? "jpg" : ext
            let target = folder.appendingPathComponent("\(clientId).\(resolvedExt)")

            do {
                try data.write(to: target, options: .atomic)
                return target.path
            } catch {
                AppLogger.error("Failed to cache pending media file: \(error.localizedDescription)")
                return nil
            }
        }.value
    }

    private func loadPendingMediaData(path: String) async -> Data? {
        let fileURL = resolveLocalFileURL(path)
        guard let fileURL else { return nil }
        return await Task.detached(priority: .utility) {
            try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }.value
    }

    private func primeMediaCache(fromLocalPath path: String, sentMessage: Message) async {
        guard sentMessage.type == .image else { return }
        guard let remoteURL = MediaURLResolver.resolve(sentMessage.mediaUrl) else { return }
        guard let localData = await loadPendingMediaData(path: path), !localData.isEmpty else { return }
        await RemoteImageStore.shared.primeImage(data: localData, for: remoteURL)
    }

    private func cleanupPendingMediaFile(path: String?) {
        guard let path, !path.isEmpty else { return }
        guard let fileURL = resolveLocalFileURL(path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            // Ignore local cache cleanup failures.
        }
    }

    private func resolveLocalFileURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://") {
            return URL(string: trimmed)
        }

        return URL(fileURLWithPath: trimmed)
    }

    private func restoreCachedStateFromDatabase() async {
        guard let userID = currentUserID else { return }

        if conversations.isEmpty,
           let data = await localCache.loadData(for: CacheKeys.conversations(userID: userID), userID: userID),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data)
        {
            conversations = decoded
        }

        if messagesByConversation.isEmpty,
           let data = await localCache.loadData(for: CacheKeys.messages(userID: userID), userID: userID),
           let decoded = try? JSONDecoder().decode([String: [Message]].self, from: data)
        {
            messagesByConversation = decoded
        }

        if pendingTextQueue.isEmpty && pendingMediaQueue.isEmpty,
           let data = await localCache.loadData(for: CacheKeys.pendingQueue(userID: userID), userID: userID),
           let decoded = decodePendingQueueSnapshot(from: data)
        {
            pendingTextQueue = decoded.text
            pendingMediaQueue = decoded.media
        }

        if currentUserSettings == nil,
           let data = await localCache.loadData(for: CacheKeys.settings(userID: userID), userID: userID),
           let decoded = try? JSONDecoder().decode(User.self, from: data)
        {
            currentUserSettings = decoded
        }
    }

    private func restoreCachedState() {
        guard let userID = currentUserID else { return }

        if conversations.isEmpty,
           let data = userDefaults.data(forKey: CacheKeys.conversations(userID: userID)),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data)
        {
            conversations = decoded
        }

        if messagesByConversation.isEmpty,
           let data = userDefaults.data(forKey: CacheKeys.messages(userID: userID)),
           let decoded = try? JSONDecoder().decode([String: [Message]].self, from: data)
        {
            messagesByConversation = decoded
        }

        if pendingTextQueue.isEmpty && pendingMediaQueue.isEmpty,
           let data = userDefaults.data(forKey: CacheKeys.pendingQueue(userID: userID)),
           let decoded = decodePendingQueueSnapshot(from: data)
        {
            pendingTextQueue = decoded.text
            pendingMediaQueue = decoded.media
        }

        if currentUserSettings == nil,
           let data = userDefaults.data(forKey: CacheKeys.settings(userID: userID)),
           let decoded = try? JSONDecoder().decode(User.self, from: data)
        {
            currentUserSettings = decoded
        }

        if syncedContactMatches.isEmpty {
            syncedContactMatches = loadCachedContactMatches()
        }
    }

    private func persistConversationsCache() {
        guard let userID = currentUserID else { return }
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        userDefaults.set(data, forKey: CacheKeys.conversations(userID: userID))
        Task { [localCache] in
            await localCache.saveData(data, for: CacheKeys.conversations(userID: userID), userID: userID)
        }
    }

    private func persistMessagesCache() {
        guard let userID = currentUserID else { return }
        guard let data = try? JSONEncoder().encode(messagesByConversation) else { return }
        userDefaults.set(data, forKey: CacheKeys.messages(userID: userID))
        Task { [localCache] in
            await localCache.saveData(data, for: CacheKeys.messages(userID: userID), userID: userID)
        }
    }

    private func persistPendingQueue() {
        guard let userID = currentUserID else { return }
        let snapshot = PendingQueueSnapshot(text: pendingTextQueue, media: pendingMediaQueue)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: CacheKeys.pendingQueue(userID: userID))
        Task { [localCache] in
            await localCache.saveData(data, for: CacheKeys.pendingQueue(userID: userID), userID: userID)
        }
    }

    private func decodePendingQueueSnapshot(from data: Data) -> PendingQueueSnapshot? {
        if let snapshot = try? JSONDecoder().decode(PendingQueueSnapshot.self, from: data) {
            return snapshot
        }

        if let legacyText = try? JSONDecoder().decode([PendingTextMessage].self, from: data) {
            return PendingQueueSnapshot(text: legacyText, media: [])
        }

        return nil
    }

    private func persistSettingsCache() {
        guard let userID = currentUserID, let currentUserSettings else { return }
        guard let data = try? JSONEncoder().encode(currentUserSettings) else { return }
        userDefaults.set(data, forKey: CacheKeys.settings(userID: userID))
        Task { [localCache] in
            await localCache.saveData(data, for: CacheKeys.settings(userID: userID), userID: userID)
        }
    }

    private func persistContactMatchesCache() {
        guard let userID = currentUserID else { return }
        let snapshot = syncedContactMatches.map { CachedContactMatch(user: $0.user, contactName: $0.contactName) }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: CacheKeys.contactMatches(userID: userID))
    }

    private func loadCachedContactMatches() -> [ContactSearchResult] {
        guard let userID = currentUserID else { return [] }
        guard let data = userDefaults.data(forKey: CacheKeys.contactMatches(userID: userID)),
              let snapshot = try? JSONDecoder().decode([CachedContactMatch].self, from: data)
        else {
            return []
        }

        return snapshot.map { item in
            ContactSearchResult(
                id: item.user.id,
                user: item.user,
                contactName: item.contactName
            )
        }
    }

    private func clearCachedState(for userID: String) {
        userDefaults.removeObject(forKey: CacheKeys.conversations(userID: userID))
        userDefaults.removeObject(forKey: CacheKeys.messages(userID: userID))
        userDefaults.removeObject(forKey: CacheKeys.pendingQueue(userID: userID))
        userDefaults.removeObject(forKey: CacheKeys.contactMatches(userID: userID))
        userDefaults.removeObject(forKey: CacheKeys.settings(userID: userID))
        Task { [localCache] in
            await localCache.removeUserData(userID: userID)
        }
    }

    private var contactNameByUserId: [String: String] {
        var mapping: [String: String] = [:]
        for match in syncedContactMatches {
            let normalized = match.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty { continue }
            if mapping[match.user.id] == nil {
                mapping[match.user.id] = normalized
            }
        }
        return mapping
    }

    private var contactPhoneByUserId: [String: String] {
        var mapping: [String: String] = [:]
        for match in syncedContactMatches {
            guard let phone = match.user.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !phone.isEmpty
            else {
                continue
            }
            if mapping[match.user.id] == nil {
                mapping[match.user.id] = phone
            }
        }
        return mapping
    }

    private func localConversationSearchResults(query: String) -> [ContactSearchResult] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return [] }

        var seen = Set<String>()
        var results: [ContactSearchResult] = []

        for conversation in conversations {
            let displayName = contactDisplayName(for: conversation).trimmingCharacters(in: .whitespacesAndNewlines)
            let username = conversation.participantUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = contactPhoneNumber(for: conversation.participantId)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let matches =
                displayName.lowercased().contains(lowered) ||
                username.lowercased().contains(lowered) ||
                (phone?.lowercased().contains(lowered) ?? false)

            guard matches else { continue }
            guard seen.insert(conversation.participantId).inserted else { continue }

            let user = User(
                id: conversation.participantId,
                username: username.isEmpty ? displayName : username,
                phoneNumber: phone,
                email: nil,
                avatarUrl: conversation.participantAvatarUrl,
                bio: nil,
                isOnline: conversation.participantIsOnline,
                lastSeen: conversation.participantLastSeen,
                lastLoginAt: nil,
                deviceId: nil,
                showOnlineStatus: nil,
                readReceiptsEnabled: nil,
                themeMode: nil,
                defaultWallpaperUrl: nil,
                totpEnabled: nil
            )

            results.append(
                ContactSearchResult(
                    id: user.id,
                    user: user,
                    contactName: displayName.isEmpty ? user.username : displayName
                )
            )
        }

        return results.sorted {
            $0.contactName.localizedCaseInsensitiveCompare($1.contactName) == .orderedAscending
        }
    }

    private func shouldAutoRetryQueue(after error: Error) -> Bool {
        if isSecureSessionSyncingError(error) {
            return true
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .network, .invalidResponse:
                return true
            default:
                return false
            }
        }

        if let socketError = error as? SocketError {
            switch socketError {
            case .notConnected, .ackTimeout, .connectTimeout:
                return true
            case .invalidAckPayload:
                return false
            }
        }

        let lowered = error.localizedDescription.lowercased()
        return lowered.contains("network") || lowered.contains("timeout")
    }

    private func shouldAutoRetryMediaUpload(after error: Error) -> Bool {
        if isQueueItemDiscardable(error: error) {
            return false
        }
        if let apiError = error as? APIError {
            switch apiError {
            case .network, .invalidResponse:
                return true
            case .server(let statusCode, _):
                return statusCode >= 500
            default:
                return false
            }
        }

        let lowered = error.localizedDescription.lowercased()
        return lowered.contains("network") || lowered.contains("timeout") || lowered.contains("offline")
    }

    private func shouldDropQueueItem(after error: Error) -> Bool {
        if isSecureSessionSyncingError(error) {
            return false
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .server(let statusCode, let message):
                let lowered = message.lowercased()
                if statusCode == 400 || statusCode == 403 || statusCode == 404 || statusCode == 409 || statusCode == 422 {
                    return true
                }
                if lowered.contains("validation failed")
                    || lowered.contains("text body is required")
                    || lowered.contains("cannot interact")
                    || lowered.contains("blocked")
                {
                    return true
                }
                return false
            case .unauthorized:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .network, .invalidResponse:
                return true
            case .server(let statusCode, _):
                return statusCode >= 500
            default:
                return false
            }
        }
        return false
    }

    private func isLikelyOfflineError(_ error: Error) -> Bool {
        let lowered = error.localizedDescription.lowercased()
        return lowered.contains("network")
            || lowered.contains("internet")
            || lowered.contains("offline")
            || lowered.contains("timed out")
    }

    func dismissTransientNotice() {
        transientNoticeTask?.cancel()
        transientNoticeTask = nil
        transientNotice = nil
    }

    func showTransientNotice(
        _ message: String,
        style: TransientNoticeStyle = .info,
        autoDismissAfter: TimeInterval = 2.6
    ) {
        transientNoticeTask?.cancel()
        let notice = TransientNotice(message: message, style: style)
        transientNotice = notice

        guard autoDismissAfter > 0 else { return }
        transientNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.transientNotice?.id == notice.id else { return }
                self?.transientNotice = nil
            }
        }
    }

    private func isSecureSessionSyncingError(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            if case .server(_, let message) = apiError {
                let lowered = message.lowercased()
                return lowered.contains("encrypted text payload is required")
                    || lowered.contains("secure chat session is still syncing")
                    || lowered.contains("public key not found")
                    || lowered.contains("key exchange is not ready")
            }
            return false
        }

        let lowered = error.localizedDescription.lowercased()
        return lowered.contains("encrypted text payload is required")
            || lowered.contains("secure chat session is still syncing")
            || lowered.contains("public key not found")
    }

    private func setError(from error: Error, fallback: String? = nil) {
        AppLogger.error("MessengerViewModel error: \(error.localizedDescription)")

        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                activeError = "Session expired. Please log in again."
            case .decodingError:
                activeError = "Server response format changed. Please retry in a moment."
            case .network:
                let message = apiError.errorDescription ?? (fallback ?? "Network error. Please try again.")
                activeError = message
                showTransientNotice(message, style: .warning)
            case .invalidURL, .invalidResponse:
                let message = fallback ?? apiError.errorDescription ?? "Request is temporarily unavailable."
                activeError = message
                showTransientNotice(message, style: .warning)
            case .server(let statusCode, let message):
                let lowered = message.lowercased()
                if lowered.contains("route not found") {
                    activeError = "This feature isn't available on current backend deployment yet."
                    showTransientNotice(activeError ?? message, style: .warning)
                    return
                }
                if lowered.contains("secure chat session is still syncing")
                    || lowered.contains("encrypted text payload is required")
                    || lowered.contains("encrypted payload is required")
                    || lowered.contains("public key not found")
                    || lowered.contains("key exchange is not ready")
                {
                    // Queue/retry will handle this silently.
                    activeError = nil
                    return
                }
                if lowered.contains("validation failed") {
                    activeError = fallback ?? "Couldn't send this message. Please try again."
                    showTransientNotice(activeError ?? message, style: .error)
                    return
                }
                if lowered.contains("blocked") || lowered.contains("cannot interact") {
                    activeError = "You cannot message this user due to privacy settings."
                    showTransientNotice(activeError ?? message, style: .warning)
                    return
                }
                if statusCode == 413 || lowered.contains("file too large") || lowered.contains("too large") {
                    activeError = "Profile photo is too large. Choose a smaller image."
                    showTransientNotice(activeError ?? message, style: .warning)
                    return
                }
                if lowered.contains("unsupported") && lowered.contains("mime") {
                    activeError = "Unsupported image format. Please choose JPG or PNG."
                    showTransientNotice(activeError ?? message, style: .warning)
                    return
                }
                if statusCode >= 500 {
                    activeError = fallback ?? "Server is temporarily busy. Please try again."
                    showTransientNotice(activeError ?? message, style: .warning)
                    return
                }
                activeError = message.isEmpty ? (fallback ?? "Request failed. Please try again.") : message
                showTransientNotice(activeError ?? "Request failed.", style: .error)
            }
            return
        }

        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lowered = message.lowercased()

        if lowered.contains("decode") {
            activeError = "Server response format changed. Please retry in a moment."
            showTransientNotice(activeError ?? "Server response changed.", style: .warning)
            return
        }

        if lowered.contains("internal server error") {
            activeError = fallback ?? "Server is temporarily busy. Please try again."
            showTransientNotice(activeError ?? "Server is temporarily busy.", style: .warning)
            return
        }

        activeError = fallback ?? message
        showTransientNotice(activeError ?? message, style: .error)
    }
}
