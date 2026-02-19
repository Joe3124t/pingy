import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatDetailView: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversation: Conversation
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var voiceRecorder = VoiceRecorderService()
    @State private var draft = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isFileImporterPresented = false

    var body: some View {
        ZStack {
            chatWallpaper

            VStack(spacing: 0) {
                topBar
                Divider().overlay(PingyTheme.border.opacity(0.4))
                messagesList
            }
        }
        .safeAreaInset(edge: .bottom) {
            composer
                .background(PingyTheme.surface)
                .overlay(Rectangle().fill(PingyTheme.border.opacity(0.35)).frame(height: 1), alignment: .top)
        }
        .onAppear {
            draft = ""
            Task {
                await viewModel.loadMessages(conversationID: conversation.conversationId)
                await viewModel.markCurrentAsSeen()
            }
        }
        .onChange(of: selectedPhotoItem) { newValue in
            guard let newValue else { return }
            Task {
                await sendPickedPhoto(item: newValue)
                selectedPhotoItem = nil
            }
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
    }

    private var topBar: some View {
        HStack(spacing: PingySpacing.sm) {
            AvatarView(url: conversation.participantAvatarUrl, fallback: conversation.participantUsername)

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.participantUsername)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)

                if conversation.participantIsOnline {
                    Label("Online", systemImage: "circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.success)
                } else {
                    Text(lastSeenText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                }
            }

            Spacer()

            Text("E2EE")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PingyTheme.primarySoft)
                .clipShape(Capsule())
        }
        .padding(.horizontal, PingySpacing.md)
        .padding(.vertical, PingySpacing.sm)
        .background(PingyTheme.surface)
    }

    private var messagesList: some View {
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
                            cryptoService: viewModel.cryptoServiceProxy,
                            isGroupedWithPrevious: isGrouped(index: index, messages: renderedMessages),
                            onReply: {
                                viewModel.setReplyTarget(message)
                            },
                            onReact: { emoji in
                                Task { await viewModel.toggleReaction(messageID: message.id, emoji: emoji) }
                            }
                        )
                        .id(message.id)
                    }

                    if let typingText = viewModel.typingByConversation[conversation.conversationId] {
                        HStack(spacing: 8) {
                            TypingIndicatorView()
                            Text("\(typingText) is typing")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(PingyTheme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, PingySpacing.sm)
                .padding(.vertical, PingySpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await viewModel.loadMessages(conversationID: conversation.conversationId, force: true)
            }
            .onChange(of: viewModel.activeMessages.count) { _ in
                if let id = viewModel.activeMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.25)) {
                        reader.scrollTo(id, anchor: .bottom)
                    }
                }
                Task { await viewModel.markCurrentAsSeen() }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let reply = viewModel.pendingReplyMessage {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to \(reply.senderUsername ?? "message")")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(PingyTheme.primaryStrong)

                        Text(reply.body?.stringValue ?? reply.mediaName ?? "Message")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(PingyTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        viewModel.setReplyTarget(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(PingyTheme.textSecondary)
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }
                .padding(.horizontal, PingySpacing.md)
                .padding(.top, 4)
            }

            HStack(alignment: .bottom, spacing: PingySpacing.sm) {
                Menu {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                        Label("Photo or video", systemImage: "photo")
                    }
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("Document", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(PingyTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PingyPressableButtonStyle())

                TextField("Write a message...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .lineLimit(1 ... 4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(PingyTheme.inputBackground)
                    .foregroundStyle(PingyTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous)
                            .stroke(PingyTheme.border, lineWidth: 1)
                    )
                    .onChange(of: draft) { newValue in
                        viewModel.sendTyping(!newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                Button {
                    Task { await toggleVoiceRecord() }
                } label: {
                    Image(systemName: voiceRecorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(voiceRecorder.isRecording ? PingyTheme.danger : PingyTheme.primaryStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PingyPressableButtonStyle())

                Button {
                    let textToSend = draft
                    draft = ""
                    viewModel.sendTyping(false)
                    PingyHaptics.softTap()
                    Task { await viewModel.sendText(textToSend) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(PingyTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PingyPressableButtonStyle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSendingMessage)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }
            .padding(.horizontal, PingySpacing.sm)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }

    private var chatWallpaper: some View {
        ZStack {
            PingyTheme.wallpaperFallback(for: colorScheme)

            if let urlString = conversation.wallpaperUrl ?? viewModel.currentUserSettings?.defaultWallpaperUrl,
               let url = URL(string: urlString)
            {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        EmptyView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: CGFloat(conversation.blurIntensity + (colorScheme == .dark ? 3 : 1)))
                            .overlay(PingyTheme.wallpaperOverlay(for: colorScheme))
                            .saturation(colorScheme == .dark ? 0.88 : 1.0)
                            .opacity(colorScheme == .dark ? 0.86 : 0.95)
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var lastSeenText: String {
        guard let value = conversation.participantLastSeen else {
            return "last seen recently"
        }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            return "last seen recently"
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return "last seen \(relative.localizedString(for: date, relativeTo: Date()))"
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

    private func sendPickedPhoto(item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let contentType = item.supportedContentTypes.first
        let isVideo = contentType?.conforms(to: .movie) ?? false
        let suggestedName = contentType?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")
        let mimeType = contentType?.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
        let type: MessageType = isVideo ? .video : .image

        await viewModel.sendMedia(
            data: data,
            fileName: "media-\(UUID().uuidString).\(suggestedName)",
            mimeType: mimeType,
            type: type
        )
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
        if mimeType == "video/mp4" {
            return .video
        }
        if mimeType.hasPrefix("audio/") {
            return .voice
        }
        return .file
    }

    private func toggleVoiceRecord() async {
        if voiceRecorder.isRecording {
            do {
                let result = try voiceRecorder.stopRecording()
                await viewModel.sendVoice(url: result.url, durationMs: result.durationMs)
            } catch {
                viewModel.activeError = error.localizedDescription
            }
        } else {
            do {
                try await voiceRecorder.startRecording()
            } catch {
                viewModel.activeError = error.localizedDescription
            }
        }
    }
}

private struct TypingIndicatorView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(PingyTheme.primary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotScale(for: index))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func dotScale(for index: Int) -> CGFloat {
        let base = phase + CGFloat(index) * 0.2
        return 0.7 + (sin(base * .pi) + 1) * 0.25
    }
}
