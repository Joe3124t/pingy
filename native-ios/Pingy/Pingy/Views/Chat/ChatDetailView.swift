import PhotosUI
import Photos
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
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var quickCameraItem: PhotosPickerItem?
    @State private var isMediaPickerPresented = false
    @State private var isQuickCameraPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var composerHeight: CGFloat = 84
    @State private var isContactInfoPresented = false
    @State private var isMicGestureActive = false
    @State private var photoPermissionAlertMessage: String?

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
        }
        .onChange(of: selectedPhotoItem) { newValue in
            guard let newValue else { return }
            Task {
                await sendPickedPhoto(item: newValue)
                selectedPhotoItem = nil
            }
        }
        .onChange(of: quickCameraItem) { newValue in
            guard let newValue else { return }
            Task {
                await sendPickedPhoto(item: newValue)
                quickCameraItem = nil
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
        .sheet(isPresented: $isContactInfoPresented) {
            NavigationStack {
                ContactInfoView(viewModel: viewModel, conversation: conversation)
            }
        }
        .photosPicker(
            isPresented: $isMediaPickerPresented,
            selection: $selectedPhotoItem,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .photosPicker(
            isPresented: $isQuickCameraPickerPresented,
            selection: $quickCameraItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .alert(
            "Photo access required",
            isPresented: Binding(
                get: { photoPermissionAlertMessage != nil },
                set: { shouldShow in
                    if !shouldShow {
                        photoPermissionAlertMessage = nil
                    }
                }
            )
        ) {
            Button("Open Settings") {
                openAppSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(photoPermissionAlertMessage ?? "Enable Photos access in Settings to send images and videos.")
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
                            cryptoService: viewModel.cryptoServiceProxy,
                            resolvePeerKey: { forceRefresh in
                                try await viewModel.resolvePeerPublicKey(
                                    conversationID: conversation.conversationId,
                                    participantID: conversation.participantId,
                                    forceRefresh: forceRefresh
                                )
                            },
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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replying to \(reply.senderUsername ?? "message")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(PingyTheme.primaryStrong)

                        Text(reply.body?.stringValue ?? reply.mediaName ?? "Message")
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
                        Task { await presentMediaPicker(imagesOnly: false) }
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
                        Task { await presentMediaPicker(imagesOnly: true) }
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
        viewModel.typingByConversation[conversation.conversationId] != nil
    }

    private var headerStatusText: String {
        if headerStatusIsTyping {
            return "typing..."
        }
        if conversation.participantIsOnline {
            return "Online"
        }
        return lastSeenText
    }

    private var hasTextToSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        var suggestedName = contentType?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")
        var mimeType = contentType?.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
        let type: MessageType = isVideo ? .video : .image
        var payload = data

        // Normalize HEIC/HEIF to JPEG so backend/media previews stay consistent across devices.
        if !isVideo, (mimeType == "image/heic" || mimeType == "image/heif"), let image = UIImage(data: data), let jpegData = image.jpegData(compressionQuality: 0.9) {
            payload = jpegData
            mimeType = "image/jpeg"
            suggestedName = "jpg"
        }

        await viewModel.sendMedia(
            data: payload,
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
        if mimeType.hasPrefix("video/") {
            return .video
        }
        if mimeType.hasPrefix("audio/") {
            return .voice
        }
        return .file
    }

    @MainActor
    private func presentMediaPicker(imagesOnly: Bool) async {
        let granted = await ensurePhotoAccess()
        guard granted else {
            photoPermissionAlertMessage = "Allow Photos access to send media from your gallery."
            return
        }

        if imagesOnly {
            isQuickCameraPickerPresented = true
        } else {
            isMediaPickerPresented = true
        }
    }

    private func ensurePhotoAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let requested = await requestPhotoAccess()
            return requested == .authorized || requested == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func requestPhotoAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsURL)
        else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }

    private func handleMicPressing(_ isPressing: Bool) async {
        if isPressing {
            guard !isMicGestureActive else { return }
            isMicGestureActive = true
            do {
                try await voiceRecorder.startRecording()
            } catch {
                isMicGestureActive = false
                viewModel.activeError = error.localizedDescription
            }
            return
        }

        guard isMicGestureActive else { return }
        isMicGestureActive = false

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
        let rawPhone = (viewModel.contactPhoneNumber(for: conversation.participantId) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dialable = rawPhone.filter { "+0123456789".contains($0) }

        guard !dialable.isEmpty else {
            viewModel.activeError = "Phone number is unavailable for this contact."
            return
        }

        guard let telURL = URL(string: "tel://\(dialable)"), UIApplication.shared.canOpenURL(telURL) else {
            viewModel.activeError = "Voice call is unavailable on this device."
            return
        }

        UIApplication.shared.open(telURL, options: [:], completionHandler: nil)
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
}
