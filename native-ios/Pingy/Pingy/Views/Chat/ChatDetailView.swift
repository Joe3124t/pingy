import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatDetailView: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversation: Conversation

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var isComposerFocused: Bool

    @StateObject private var voiceRecorder = VoiceRecorderService()

    @State private var draft = ""
    @State private var isNativeMediaPickerPresented = false
    @State private var isMediaComposerPresented = false
    @State private var composedMediaItems: [MediaComposerItem] = []
    @State private var isFileImporterPresented = false
    @State private var composerHeight: CGFloat = 84
    @State private var isContactInfoPresented = false
    @State private var mediaViewerState: ChatMediaViewerState?
    @State private var isMicGestureActive = false
    @State private var activeCallSession: InAppCallSession?
    @State private var callAutoConnectTask: Task<Void, Never>?

    private let mediaManager = MediaManager()
    private let uploadService = UploadService()

    var body: some View {
        ZStack {
            chatWallpaper

            VStack(spacing: 0) {
                topBar
                Divider().overlay(PingyTheme.border.opacity(0.4))
                messagesList(bottomInset: composerHeight + 16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { composerHeight = geometry.size.height }
                            .onChange(of: geometry.size.height) { composerHeight = $0 }
                    }
                )
        }
        .background(PingyTheme.background)
        .onAppear {
            if horizontalSizeClass == .compact {
                viewModel.isCompactChatDetailPresented = true
            }
            draft = ""
            Task {
                await viewModel.loadMessages(conversationID: conversation.conversationId)
                await viewModel.markCurrentAsSeen()
            }
        }
        .onDisappear {
            if horizontalSizeClass == .compact {
                viewModel.isCompactChatDetailPresented = false
            }
            callAutoConnectTask?.cancel()
            if voiceRecorder.isRecording {
                _ = try? voiceRecorder.stopRecording()
            }
            viewModel.sendTyping(false)
            viewModel.sendRecordingIndicator(false)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .movie, .pdf, .data],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            Task {
                await sendPickedFile(url: url)
            }
        }
        .sheet(isPresented: $isContactInfoPresented) {
                NavigationStack {
                    ContactInfoView(viewModel: viewModel, conversation: conversation)
                }
            }
        .sheet(isPresented: $isNativeMediaPickerPresented) {
            NativeMediaPickerView(
                selectionLimit: 4,
                onCancel: {
                    isNativeMediaPickerPresented = false
                },
                onFinish: { results in
                    Task {
                        await MainActor.run {
                            isNativeMediaPickerPresented = false
                        }
                        guard !results.isEmpty else { return }
                        let items = await mediaManager.loadComposerItems(from: results, source: .gallery)
                        await MainActor.run {
                            guard !items.isEmpty else {
                                viewModel.showTransientNotice(
                                    "Couldn't read selected media. Try another photo.",
                                    style: .warning
                                )
                                return
                            }
                            composedMediaItems = items
                            isMediaComposerPresented = true
                        }
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $isMediaComposerPresented, onDismiss: {
            composedMediaItems = []
        }) {
            MediaComposerView(
                items: composedMediaItems,
                recipientName: participantDisplayName,
                onClose: {
                    isMediaComposerPresented = false
                },
                onSend: { items, caption, hdEnabled in
                    let batchItems = items
                    let batchCaption = caption
                    let useHD = hdEnabled
                    isMediaComposerPresented = false

                    Task {
                        await uploadService.uploadMediaBatch(
                            items: batchItems,
                            caption: batchCaption,
                            hdEnabled: useHD
                        ) { item, uploadData, caption in
                            guard !uploadData.isEmpty else {
                                await MainActor.run {
                                    viewModel.showTransientNotice(
                                        "Skipped one file because it could not be prepared.",
                                        style: .warning
                                    )
                                }
                                return
                            }
                            await viewModel.sendMedia(
                                data: uploadData,
                                fileName: item.fileName,
                                mimeType: item.mimeType,
                                type: .image,
                                body: caption
                            )
                        }
                    }
                }
            )
        }
        .fullScreenCover(item: $mediaViewerState) { state in
            ChatMediaViewer(
                entries: state.entries,
                initialIndex: state.initialIndex,
                currentUserID: viewModel.currentUserID,
                onDismiss: {
                    mediaViewerState = nil
                },
                onReply: { message in
                    viewModel.setReplyTarget(message)
                    mediaViewerState = nil
                },
                onDeleteOwnMessage: { message in
                    viewModel.deleteMessageLocally(messageID: message.id, conversationID: message.conversationId)
                    mediaViewerState = nil
                }
            )
        }
        .fullScreenCover(item: $activeCallSession) { session in
            InAppVoiceCallView(
                session: session,
                onToggleMute: {
                    toggleCallMute()
                },
                onToggleSpeaker: {
                    toggleCallSpeaker()
                },
                onEnd: {
                    endCurrentCall()
                }
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(spacing: PingySpacing.sm) {
            if horizontalSizeClass == .compact {
                Button {
                    viewModel.isCompactChatDetailPresented = false
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(PingyTheme.primaryStrong)
                        .frame(width: 34, height: 34)
                        .background(PingyTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(PingyPressableButtonStyle())
            }

            Button {
                isContactInfoPresented = true
            } label: {
                HStack(spacing: 10) {
                    AvatarView(
                        url: conversation.participantAvatarUrl,
                        fallback: participantDisplayName,
                        size: 38,
                        cornerRadius: 19
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(participantDisplayName)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(PingyTheme.textPrimary)
                            .lineLimit(1)

                        Text(headerStatusText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(headerStatusIsTyping ? PingyTheme.primaryStrong : PingyTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                startVoiceCall()
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PingyTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(PingyTheme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(PingyPressableButtonStyle())

            Button {
                viewModel.isChatSettingsPresented = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(PingyTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(PingyTheme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .padding(.horizontal, PingySpacing.md)
        .padding(.vertical, 10)
        .background(PingyTheme.surface)
    }

    private func messagesList(bottomInset: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if viewModel.isLoadingMessages, viewModel.activeMessages.isEmpty {
                        ProgressView("Loading messages...")
                            .padding(.top, 32)
                            .foregroundStyle(PingyTheme.textSecondary)
                    }

                    ForEach(Array(renderedMessages.enumerated()), id: \.element.id) { index, message in
                        MessageBubbleView(
                            message: message,
                            conversation: conversation,
                            currentUserID: viewModel.currentUserID,
                            isGroupedWithPrevious: isGrouped(index: index, messages: renderedMessages),
                            decryptedText: viewModel.decryptedBody(for: message),
                            uploadProgress: viewModel.mediaUploadProgress(for: message),
                            canRetryUpload: viewModel.canRetryMediaUpload(for: message),
                            outgoingState: viewModel.outgoingState(for: message),
                            canRetryText: viewModel.canRetryTextMessage(for: message),
                            onReply: {
                                viewModel.setReplyTarget(message)
                            },
                            onReact: { emoji in
                                Task { await viewModel.toggleReaction(messageID: message.id, emoji: emoji) }
                            },
                            onRetryUpload: {
                                viewModel.retryPendingMediaUpload(for: message)
                            },
                            onRetryText: {
                                viewModel.retryPendingTextMessage(for: message)
                            },
                            onOpenImage: { tappedMessage, _ in
                                openMediaViewer(for: tappedMessage)
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, PingySpacing.sm)
                .padding(.top, PingySpacing.md)
                .padding(.bottom, bottomInset)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                await viewModel.loadMessages(
                    conversationID: conversation.conversationId,
                    force: true,
                    suppressNetworkAlert: true
                )
            }
            .onTapGesture {
                isComposerFocused = false
            }
            .onChange(of: viewModel.activeMessages.count) { _ in
                if let id = viewModel.activeMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        reader.scrollTo(id, anchor: .bottom)
                    }
                }
                Task { await viewModel.markCurrentAsSeen() }
            }
            .onChange(of: isComposerFocused) { focused in
                if focused, let id = viewModel.activeMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        reader.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let reply = viewModel.pendingReplyMessage {
                let replySender = (reply.senderUsername?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? (reply.senderUsername ?? "message")
                    : "message"
                let replyPreviewText = MessageBodyFormatter.previewText(
                    from: reply.body,
                    fallback: reply.mediaName ?? "Message"
                )

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to \(replySender)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(PingyTheme.primaryStrong)

                        Text(replyPreviewText)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(PingyTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        viewModel.setReplyTarget(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(PingyTheme.textSecondary)
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }
                .padding(.horizontal, PingySpacing.md)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button {
                        isNativeMediaPickerPresented = true
                    } label: {
                        Label("Photo or video", systemImage: "photo")
                    }
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("Document", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(PingyTheme.primaryStrong)
                        .frame(width: 40, height: 40)
                        .background(PingyTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(PingyPressableButtonStyle())

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Write a message...", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .lineLimit(1 ... 5)
                        .focused($isComposerFocused)
                        .onChange(of: draft) { newValue in
                            viewModel.sendTyping(!newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                    Button {
                        isNativeMediaPickerPresented = true
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PingyTheme.textSecondary)
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(PingyTheme.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PingyTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                if hasTextToSend {
                    Button {
                        let textToSend = draft
                        draft = ""
                        isComposerFocused = true
                        viewModel.sendTyping(false)
                        PingyHaptics.softTap()
                        Task { await viewModel.sendText(textToSend) }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(PingyTheme.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                } else {
                    Button {} label: {
                        Image(systemName: voiceRecorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(voiceRecorder.isRecording ? PingyTheme.danger : PingyTheme.primaryStrong)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                    .onLongPressGesture(minimumDuration: 0.12, pressing: { isPressing in
                        Task { await handleMicPressing(isPressing) }
                    }, perform: {})
                }
            }
            .padding(.horizontal, PingySpacing.sm)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(PingyTheme.surface)
        .overlay(Rectangle().fill(PingyTheme.border.opacity(0.35)).frame(height: 1), alignment: .top)
    }

    private var chatWallpaper: some View {
        GeometryReader { geometry in
            ZStack {
                PingyTheme.wallpaperFallback(for: colorScheme)

                if let url = MediaURLResolver.resolve(conversation.wallpaperUrl ?? viewModel.currentUserSettings?.defaultWallpaperUrl) {
                    if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                        wallpaperImage(
                            Image(uiImage: image),
                            canvasSize: geometry.size
                        )
                    } else {
                        CachedRemoteImage(url: url) { image in
                            wallpaperImage(image, canvasSize: geometry.size)
                        } placeholder: {
                            EmptyView()
                        } failure: {
                            EmptyView()
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private var participantDisplayName: String {
        viewModel.contactDisplayName(for: conversation)
    }

    private var headerStatusIsTyping: Bool {
        let status = viewModel.presenceStatus(for: conversation)
        return status.highlighted
    }

    private var headerStatusText: String {
        _ = viewModel.activeDurationTick
        viewModel.presenceStatus(for: conversation).text
    }

    private var hasTextToSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var renderedMessages: [Message] {
        viewModel.activeMessages
    }

    private func isGrouped(index: Int, messages: [Message]) -> Bool {
        guard index > 0 else { return false }

        let current = messages[index]
        let previous = messages[index - 1]
        guard current.senderId == previous.senderId else { return false }

        let formatter = ISO8601DateFormatter()
        guard let currentDate = formatter.date(from: current.createdAt),
              let previousDate = formatter.date(from: previous.createdAt)
        else {
            return false
        }

        return currentDate.timeIntervalSince(previousDate) < 180
    }

    private func sendPickedFile(url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let mimeType = mimeTypeForFileExtension(ext)
        let type = messageTypeForMimeType(mimeType)

        await viewModel.sendMedia(
            data: data,
            fileName: url.lastPathComponent,
            mimeType: mimeType,
            type: type
        )
    }

    private func mimeTypeForFileExtension(_ ext: String) -> String {
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        case "mp4":
            return "video/mp4"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "ogg":
            return "audio/ogg"
        case "pdf":
            return "application/pdf"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default:
            if let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType {
                return mimeType
            }
            return "application/octet-stream"
        }
    }

    private func messageTypeForMimeType(_ mimeType: String) -> MessageType {
        if mimeType.hasPrefix("image/") {
            return .image
        }
        if mimeType.hasPrefix("video/") {
            return .video
        }
        if mimeType.hasPrefix("audio/") {
            return .voice
        }
        return .file
    }

    private func handleMicPressing(_ isPressing: Bool) async {
        if isPressing {
            guard !isMicGestureActive else { return }
            isMicGestureActive = true
            viewModel.sendRecordingIndicator(true)
            do {
                try await voiceRecorder.startRecording()
            } catch {
                isMicGestureActive = false
                viewModel.sendRecordingIndicator(false)
                viewModel.activeError = error.localizedDescription
            }
            return
        }

        guard isMicGestureActive else { return }
        isMicGestureActive = false
        viewModel.sendRecordingIndicator(false)

        guard voiceRecorder.isRecording else { return }

        do {
            let result = try voiceRecorder.stopRecording()
            if result.durationMs > 200 {
                await viewModel.sendVoice(url: result.url, durationMs: result.durationMs)
            }
        } catch {
            viewModel.activeError = error.localizedDescription
        }
    }

    private func startVoiceCall() {
        guard activeCallSession == nil else { return }
        let callId = UUID().uuidString
        activeCallSession = InAppCallSession(
            id: callId,
            conversationId: conversation.conversationId,
            participantId: conversation.participantId,
            participantName: participantDisplayName,
            participantAvatarURL: conversation.participantAvatarUrl,
            status: .ringing,
            startedAt: nil,
            isMuted: false,
            isSpeakerEnabled: false
        )
        viewModel.sendCallInvite(callId: callId, conversationId: conversation.conversationId, participantID: conversation.participantId)

        callAutoConnectTask?.cancel()
        callAutoConnectTask = Task { [conversationId = conversation.conversationId, participantId = conversation.participantId] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            await MainActor.run {
                guard var session = activeCallSession, session.conversationId == conversationId else { return }
                session.status = .connected
                session.startedAt = Date()
                activeCallSession = session
                viewModel.sendCallAccepted(callId: session.id, conversationId: conversationId, participantID: participantId)
            }
        }
    }

    private func toggleCallMute() {
        guard var session = activeCallSession else { return }
        session.isMuted.toggle()
        activeCallSession = session
    }

    private func toggleCallSpeaker() {
        guard var session = activeCallSession else { return }
        session.isSpeakerEnabled.toggle()
        activeCallSession = session
    }

    private func endCurrentCall() {
        guard let session = activeCallSession else { return }
        callAutoConnectTask?.cancel()
        let isConnected = session.startedAt != nil
        let duration = isConnected ? Int(Date().timeIntervalSince(session.startedAt ?? Date())) : 0
        viewModel.sendCallEnded(
            callId: session.id,
            conversationId: session.conversationId,
            participantID: session.participantId,
            status: session.startedAt == nil ? .missed : .ended
        )
        if let userID = viewModel.currentUserID, !userID.isEmpty {
            Task {
                await CallLogService.shared.append(
                    CallLogEntry(
                        id: UUID().uuidString,
                        conversationID: session.conversationId,
                        participantID: session.participantId,
                        participantName: session.participantName,
                        participantAvatarURL: session.participantAvatarURL,
                        direction: .outgoing,
                        type: .voice,
                        createdAt: Date(),
                        durationSeconds: duration
                    ),
                    for: userID
                )
            }
        }
        activeCallSession = nil
    }

    @ViewBuilder
    private func wallpaperImage(_ image: Image, canvasSize: CGSize) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
            .blur(radius: CGFloat(max(0, conversation.blurIntensity)))
            .overlay(PingyTheme.wallpaperOverlay(for: colorScheme))
    }

    private var galleryEntries: [ChatMediaGalleryEntry] {
        renderedMessages.compactMap { message in
            guard message.type == .image,
                  let url = MediaURLResolver.resolve(message.mediaUrl)
            else {
                return nil
            }

            return ChatMediaGalleryEntry(
                id: message.id,
                message: message,
                url: url
            )
        }
    }

    private func openMediaViewer(for tappedMessage: Message) {
        let entries = galleryEntries
        guard !entries.isEmpty else { return }
        guard let index = entries.firstIndex(where: { $0.message.id == tappedMessage.id }) else { return }

        mediaViewerState = ChatMediaViewerState(
            entries: entries,
            initialIndex: index
        )
    }
}
