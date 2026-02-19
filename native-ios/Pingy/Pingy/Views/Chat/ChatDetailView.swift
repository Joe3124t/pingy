import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatDetailView: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversation: Conversation

    @StateObject private var voiceRecorder = VoiceRecorderService()
    @State private var draft = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var pendingScrollID: String?

    var body: some View {
        ZStack {
            chatWallpaper
            VStack(spacing: 0) {
                topBar
                Divider().overlay(Color.white.opacity(0.08))
                messagesList
            }
        }
        .safeAreaInset(edge: .bottom) {
            composer
                .background(.ultraThinMaterial)
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
        HStack(spacing: 10) {
            AvatarView(url: conversation.participantAvatarUrl, fallback: conversation.participantUsername)

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.participantUsername)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if conversation.participantIsOnline {
                    Label("Online", systemImage: "circle.fill")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.green)
                } else {
                    Text(lastSeenText)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            Spacer()
            Text("E2EE")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.20))
    }

    private var messagesList: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.activeMessages) { message in
                        MessageBubbleView(
                            message: message,
                            conversation: conversation,
                            currentUserID: viewModel.currentUserID,
                            cryptoService: viewModel.cryptoServiceProxy,
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
                        HStack {
                            Text("\(typingText) is typing...")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.activeMessages.count) { _ in
                pendingScrollID = viewModel.activeMessages.last?.id
                if let id = pendingScrollID {
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
                            .foregroundStyle(.secondary)
                        Text(reply.body?.stringValue ?? reply.mediaName ?? "Message")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        viewModel.setReplyTarget(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(alignment: .bottom, spacing: 10) {
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
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                TextField("Write a message...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .lineLimit(1 ... 4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.10))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onChange(of: draft) { newValue in
                        viewModel.sendTyping(!newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                Button {
                    Task { await toggleVoiceRecord() }
                } label: {
                    Image(systemName: voiceRecorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(voiceRecorder.isRecording ? Color.red : Color.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.red.opacity(voiceRecorder.isRecording ? 0.8 : 0), lineWidth: 2)
                                .scaleEffect(voiceRecorder.isRecording ? 1.12 : 1.0)
                                .opacity(voiceRecorder.isRecording ? 0.25 : 0)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: voiceRecorder.isRecording)
                        )
                }

                Button {
                    let textToSend = draft
                    draft = ""
                    viewModel.sendTyping(false)
                    Task { await viewModel.sendText(textToSend) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color(red: 0.02, green: 0.64, blue: 0.83))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSendingMessage)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color.black.opacity(0.15))
    }

    private var chatWallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.06, blue: 0.20), Color(red: 0.01, green: 0.11, blue: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

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
                            .blur(radius: CGFloat(conversation.blurIntensity))
                            .opacity(0.45)
                            .overlay(Color.black.opacity(0.25))
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .ignoresSafeArea()
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
