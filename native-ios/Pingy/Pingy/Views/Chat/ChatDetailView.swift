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
    @FocusState private var isSearchFieldFocused: Bool

    @StateObject private var voiceRecorder = VoiceRecorderService()

    @State private var draft = ""
    @State private var isSearchMode = false
    @State private var searchQuery = ""
    @State private var searchResults: [ChatSearchMatch] = []
    @State private var searchRangesByMessageID: [String: [NSRange]] = [:]
    @State private var selectedSearchResultIndex = 0
    @State private var pendingSearchJumpMessageID: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var starredMessageIDs = Set<String>()
    @State private var isNativeMediaPickerPresented = false
    @State private var isMediaComposerPresented = false
    @State private var composedMediaItems: [MediaComposerItem] = []
    @State private var isFileImporterPresented = false
    @State private var composerHeight: CGFloat = 84
    @State private var isContactInfoPresented = false
    @State private var mediaViewerState: ChatMediaViewerState?
    @State private var isMicGestureActive = false
    @State private var shouldScrollToInitialPosition = true
    @State private var pendingInitialJumpToLatest = false
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var bottomAnchorY: CGFloat = .greatestFiniteMagnitude
    @State private var chatOpenedAt: Date = .distantPast
    @State private var isChatLocked = false
    @State private var unlockPasscode = ""
    @State private var contextualMessage: Message?
    @State private var messageFramesByID: [String: CGRect] = [:]

    private let mediaManager = MediaManager()
    private let uploadService = UploadService()
    private let chatBottomAnchorID = "chat-bottom-anchor"

    var body: some View {
        ZStack {
            chatWallpaper

            VStack(spacing: 0) {
                topBar
                if isSearchMode {
                    searchBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Divider().overlay(PingyTheme.border.opacity(0.4))
                messagesList(bottomInset: composerHeight + 16)
            }
            .allowsHitTesting(!isChatLocked)
            .blur(radius: isChatLocked ? 3 : 0)

            if isChatLocked {
                chatLockOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .coordinateSpace(name: "chat-root-space")
        .overlay {
            GeometryReader { proxy in
                if let contextualMessage,
                   let frame = messageFramesByID[contextualMessage.id]
                {
                    floatingMessageContextMenu(
                        for: contextualMessage,
                        frame: frame,
                        canvasSize: proxy.size
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
                .allowsHitTesting(!isChatLocked)
                .opacity(isChatLocked ? 0 : 1)
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
            shouldScrollToInitialPosition = true
            pendingInitialJumpToLatest = true
            bottomAnchorY = .greatestFiniteMagnitude
            chatOpenedAt = Date()
            starredMessageIDs = Set(UserDefaults.standard.stringArray(forKey: starredMessagesKey) ?? [])
            refreshLockState()
            Task {
                if viewModel.selectedConversationID != conversation.conversationId {
                    await viewModel.selectConversation(conversation.conversationId)
                } else {
                    await viewModel.markCurrentAsSeen()
                }
            }
        }
        .onDisappear {
            if horizontalSizeClass == .compact {
                viewModel.isCompactChatDetailPresented = false
            }
            searchTask?.cancel()
            if voiceRecorder.isRecording {
                _ = try? voiceRecorder.stopRecording()
            }
            viewModel.sendTyping(false)
            viewModel.sendRecordingIndicator(false)
            contextualMessage = nil
        }
        .onChange(of: isContactInfoPresented) { presented in
            if !presented {
                refreshLockState()
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
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: searchQuery) { _ in
            refreshSearchResults()
        }
        .onChange(of: renderedMessages.count) { _ in
            if isSearchMode {
                refreshSearchResults()
            }
        }
        .onChange(of: renderedMessages.last?.id) { _ in
            if isSearchMode {
                refreshSearchResults()
            }
        }
        .onChange(of: isSearchMode) { enabled in
            if enabled {
                refreshSearchResults()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    isSearchFieldFocused = true
                }
            } else {
                searchTask?.cancel()
                searchTask = nil
                searchQuery = ""
                searchResults = []
                searchRangesByMessageID = [:]
                selectedSearchResultIndex = 0
                pendingSearchJumpMessageID = nil
                isSearchFieldFocused = false
            }
        }
        .pingyPrefersBottomBarHidden()
    }

    private var chatLockOverlay: some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(PingyTheme.primaryStrong)

                Text("This chat is locked")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)

                Text("Enter chat password to open conversation.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
                    .multilineTextAlignment(.center)

                SecureField("Chat password", text: $unlockPasscode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(PingyTheme.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PingyTheme.border.opacity(0.6), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .submitLabel(.done)
                    .onSubmit {
                        unlockChat()
                    }

                HStack(spacing: 10) {
                    Button {
                        viewModel.isCompactChatDetailPresented = false
                        dismiss()
                    } label: {
                        Text("Back")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(PingyTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(PingyTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PingyPressableButtonStyle())

                    Button {
                        unlockChat()
                    } label: {
                        Text("Unlock")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(PingyTheme.primaryStrong)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }
            }
            .padding(PingySpacing.md)
            .background(PingyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous)
                    .stroke(PingyTheme.border.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 8)
            .padding(.horizontal, PingySpacing.lg)
        }
    }

    private var topBar: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 0.9)
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.20),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 24)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.3), radius: 16, x: 0, y: 9)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if horizontalSizeClass == .compact {
                        Button {
                            viewModel.isCompactChatDetailPresented = false
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.95))
                                .frame(width: 42, height: 42)
                                .background(.ultraThinMaterial)
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.13), lineWidth: 0.8)
                                )
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 3)
                        }
                        .buttonStyle(PingyPressableButtonStyle())
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            startVoiceCall()
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.92))
                                .frame(width: 42, height: 42)
                                .background(.ultraThinMaterial)
                                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 3)
                        }
                        .buttonStyle(PingyPressableButtonStyle())

                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                isSearchMode.toggle()
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.92))
                                .frame(width: 42, height: 42)
                                .background(.ultraThinMaterial)
                                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 3)
                        }
                        .buttonStyle(PingyPressableButtonStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Button {
                    isContactInfoPresented = true
                } label: {
                    VStack(spacing: 3) {
                        Text(participantDisplayName)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.97))
                            .lineLimit(1)

                        Text(headerStatusText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(
                                headerStatusIsTyping
                                    ? PingyTheme.primaryStrong.opacity(0.98)
                                    : Color.white.opacity(0.68)
                            )
                            .lineLimit(1)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            headerAvatar
                .offset(y: -31)
                .shadow(color: Color.black.opacity(0.25), radius: 10, y: 5)
        }
        .frame(height: 110)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var headerAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.26))

            if let avatarURL = MediaURLResolver.resolve(conversation.participantAvatarUrl) {
                CachedRemoteImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                } placeholder: {
                    avatarFallback
                } failure: {
                    avatarFallback
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.24), lineWidth: 1.0)
        )
    }

    private var avatarFallback: some View {
        ZStack {
            LinearGradient(
                colors: [PingyTheme.primary, PingyTheme.primaryStrong],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(String(participantDisplayName.prefix(1)).uppercased())
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
    }

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PingyTheme.textSecondary)

                    TextField("Search in chat", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                        .focused($isSearchFieldFocused)

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(PingyTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(PingyTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        isSearchMode = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PingyTheme.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(PingyTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(PingyPressableButtonStyle())
            }

            HStack(spacing: 10) {
                Text(searchCounterText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)

                Spacer()

                Button {
                    selectPreviousSearchResult()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PingyTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(PingyTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(PingyPressableButtonStyle())
                .disabled(searchResults.isEmpty)

                Button {
                    selectNextSearchResult()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PingyTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(PingyTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(PingyPressableButtonStyle())
                .disabled(searchResults.isEmpty)
            }
        }
        .padding(.horizontal, PingySpacing.md)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .background(PingyTheme.surface)
    }

    private func messagesList(bottomInset: CGFloat) -> some View {
        GeometryReader { container in
            ScrollViewReader { reader in
                ZStack(alignment: .bottomTrailing) {
                    let messages = renderedMessages
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            if viewModel.isLoadingMessages, viewModel.activeMessages.isEmpty {
                                ProgressView("Loading messages...")
                                    .padding(.top, 32)
                                    .foregroundStyle(PingyTheme.textSecondary)
                            }

                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                let highlightRanges = isSearchMode ? (searchRangesByMessageID[message.id] ?? []) : []
                                let isStarred = starredMessageIDs.contains(message.id)

                                MessageBubbleView(
                                    message: message,
                                    conversation: conversation,
                                    currentUserID: viewModel.currentUserID,
                                    isGroupedWithPrevious: isGrouped(index: index, messages: messages),
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
                                    },
                                    onLongPress: {
                                        presentFloatingActions(for: message)
                                    },
                                    searchHighlightRanges: highlightRanges,
                                    isStarred: isStarred,
                                    onForward: {
                                        forwardMessage(message)
                                    },
                                    onToggleStar: {
                                        toggleStar(for: message.id)
                                    },
                                    onDeleteForMe: {
                                        viewModel.deleteMessageLocally(
                                            messageID: message.id,
                                            conversationID: conversation.conversationId
                                        )
                                    }
                                )
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ChatMessageFramePreferenceKey.self,
                                            value: [message.id: geo.frame(in: .named("chat-root-space"))]
                                        )
                                    }
                                )
                                .id(message.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(chatBottomAnchorID)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ChatBottomAnchorPreferenceKey.self,
                                            value: geo.frame(in: .named("chat-scroll-space")).minY
                                        )
                                    }
                                )
                        }
                        .padding(.horizontal, PingySpacing.sm)
                        .padding(.top, PingySpacing.md)
                        .padding(.bottom, bottomInset)
                    }
                    .coordinateSpace(name: "chat-scroll-space")
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
                        dismissFloatingActions()
                    }
                    .onAppear {
                        scrollViewportHeight = container.size.height
                        performInitialScrollIfNeeded(using: reader)
                    }
                    .onChange(of: container.size.height) { newHeight in
                        scrollViewportHeight = newHeight
                    }
                    .onPreferenceChange(ChatBottomAnchorPreferenceKey.self) { value in
                        bottomAnchorY = value
                    }
                    .onPreferenceChange(ChatMessageFramePreferenceKey.self) { value in
                        messageFramesByID = value
                    }
                    .onChange(of: renderedMessages.count) { _ in
                        handleMessageListChange(using: reader)

                        Task { await viewModel.markCurrentAsSeen() }
                    }
                    .onChange(of: renderedMessages.last?.id) { _ in
                        handleMessageListChange(using: reader)
                    }
                    .onChange(of: pendingSearchJumpMessageID) { targetID in
                        guard let targetID else { return }
                        withAnimation(.easeInOut(duration: 0.24)) {
                            reader.scrollTo(targetID, anchor: .center)
                        }
                    }
                    .onChange(of: isComposerFocused) { focused in
                        if focused {
                            scrollToLatest(using: reader, animated: true)
                        }
                    }

                    if shouldShowJumpToLatestButton {
                        Button {
                            scrollToLatest(using: reader, animated: true)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(PingyTheme.primaryStrong)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
                        }
                        .buttonStyle(PingyPressableButtonStyle())
                        .padding(.trailing, PingySpacing.md)
                        .padding(.bottom, 18)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let reply = viewModel.pendingReplyMessage {
                let replySender = (reply.senderUsername?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? (reply.senderUsername ?? "Unknown")
                    : "Unknown"
                let replyPreviewText = MessageBodyFormatter.previewText(
                    from: reply.body,
                    fallback: MessageBodyFormatter.fallbackLabel(for: reply.type, mediaName: reply.mediaName)
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
                SpaceParticleField(seed: conversation.conversationId.hashValue)
                    .opacity(0.28)
                RadialGradient(
                    colors: [
                        Color(red: 0.35, green: 0.72, blue: 0.82).opacity(0.22),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: 30,
                    endRadius: 390
                )
                .blendMode(.screen)
                .allowsHitTesting(false)

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

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.14),
                        Color.black.opacity(0.28),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
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
        return viewModel.presenceStatus(for: conversation).text
    }

    private var hasTextToSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var starredMessagesKey: String {
        "pingy.chat.starred.messages.\(conversation.conversationId)"
    }

    private var searchCounterText: String {
        guard !searchResults.isEmpty else { return "0/0" }
        let index = min(max(0, selectedSearchResultIndex), max(0, searchResults.count - 1))
        return "\(index + 1)/\(searchResults.count)"
    }

    private var renderedMessages: [Message] {
        viewModel.messages(for: conversation.conversationId)
    }

    private var isNearBottom: Bool {
        guard scrollViewportHeight > 0 else { return true }
        return bottomAnchorY <= (scrollViewportHeight + 28)
    }

    private var shouldShowJumpToLatestButton: Bool {
        !renderedMessages.isEmpty && !isNearBottom
    }

    private var shouldAutoScrollToLatest: Bool {
        if pendingInitialJumpToLatest {
            return true
        }
        if Date().timeIntervalSince(chatOpenedAt) < 8 {
            return true
        }
        if isNearBottom {
            return true
        }
        guard let lastMessage = renderedMessages.last else { return false }
        return lastMessage.senderId == viewModel.currentUserID
    }

    private func performInitialScrollIfNeeded(using reader: ScrollViewProxy) {
        guard shouldScrollToInitialPosition else { return }
        guard let lastID = renderedMessages.last?.id else { return }

        shouldScrollToInitialPosition = false

        DispatchQueue.main.async {
            reader.scrollTo(lastID, anchor: .bottom)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeOut(duration: 0.18)) {
                    reader.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private func handleMessageListChange(using reader: ScrollViewProxy) {
        if pendingInitialJumpToLatest {
            pendingInitialJumpToLatest = false
            shouldScrollToInitialPosition = false
            scrollToLatest(using: reader, animated: false)
            return
        }

        if shouldScrollToInitialPosition {
            performInitialScrollIfNeeded(using: reader)
            return
        }

        if shouldAutoScrollToLatest {
            scrollToLatest(using: reader, animated: true)
        }
    }

    private func scrollToLatest(using reader: ScrollViewProxy, animated: Bool) {
        guard let lastID = renderedMessages.last?.id else { return }

        let action = {
            reader.scrollTo(lastID, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                action()
            }
        } else {
            action()
        }
    }

    private func refreshSearchResults() {
        searchTask?.cancel()

        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearchMode, !normalizedQuery.isEmpty else {
            searchResults = []
            searchRangesByMessageID = [:]
            selectedSearchResultIndex = 0
            pendingSearchJumpMessageID = nil
            return
        }

        let snapshotMessages = renderedMessages
        let decryptedLookup = snapshotMessages.reduce(into: [String: String]()) { mapping, message in
            if let decrypted = viewModel.decryptedBody(for: message) {
                mapping[message.id] = decrypted
            }
        }
        let previousSelectedMatchID = searchResults.indices.contains(selectedSearchResultIndex)
            ? searchResults[selectedSearchResultIndex].id
            : nil

        searchTask = Task {
            let resultSet = await Task.detached(priority: .userInitiated) {
                ChatSearchEngine.search(
                    query: normalizedQuery,
                    messages: snapshotMessages,
                    decryptedBodyByID: decryptedLookup
                )
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                searchResults = resultSet.matches
                searchRangesByMessageID = resultSet.rangesByMessageID

                guard !resultSet.matches.isEmpty else {
                    selectedSearchResultIndex = 0
                    pendingSearchJumpMessageID = nil
                    return
                }

                if let previousSelectedMatchID,
                   let preservedIndex = resultSet.matches.firstIndex(where: { $0.id == previousSelectedMatchID })
                {
                    selectedSearchResultIndex = preservedIndex
                } else {
                    selectedSearchResultIndex = 0
                }

                pendingSearchJumpMessageID = resultSet.matches[selectedSearchResultIndex].messageID
            }
        }
    }

    private func selectNextSearchResult() {
        guard !searchResults.isEmpty else { return }
        selectedSearchResultIndex = (selectedSearchResultIndex + 1) % searchResults.count
        pendingSearchJumpMessageID = searchResults[selectedSearchResultIndex].messageID
        PingyHaptics.softTap()
    }

    private func selectPreviousSearchResult() {
        guard !searchResults.isEmpty else { return }
        selectedSearchResultIndex = (selectedSearchResultIndex - 1 + searchResults.count) % searchResults.count
        pendingSearchJumpMessageID = searchResults[selectedSearchResultIndex].messageID
        PingyHaptics.softTap()
    }

    private func forwardMessage(_ message: Message) {
        let decrypted = viewModel.decryptedBody(for: message)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = message.body?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rendered = MessageBodyFormatter.previewText(from: message.body, fallback: "")
        let payload = !decrypted.isEmpty ? decrypted : (normalized.isEmpty ? rendered : normalized)

        guard !payload.isEmpty else {
            viewModel.showTransientNotice("Forward for this message type will be added soon.", style: .warning)
            return
        }

        draft = payload
        isComposerFocused = true
        PingyHaptics.softTap()
    }

    private func toggleStar(for messageID: String) {
        if starredMessageIDs.contains(messageID) {
            starredMessageIDs.remove(messageID)
            viewModel.showTransientNotice("Removed from starred.", style: .info, autoDismissAfter: 1.4)
        } else {
            starredMessageIDs.insert(messageID)
            viewModel.showTransientNotice("Added to starred.", style: .success, autoDismissAfter: 1.4)
        }

        UserDefaults.standard.set(Array(starredMessageIDs), forKey: starredMessagesKey)
    }

    private var floatingReactions: [String] {
        [
            "\u{2764}\u{FE0F}",
            "\u{1F604}",
            "\u{1F979}",
            "\u{1F62D}",
            "\u{1F621}",
            "\u{1F44D}",
            "\u{1F44E}",
        ]
    }

    private func presentFloatingActions(for message: Message) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            contextualMessage = message
        }
        PingyHaptics.softTap()
    }

    private func dismissFloatingActions() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            contextualMessage = nil
        }
    }

    @ViewBuilder
    private func floatingMessageContextMenu(
        for message: Message,
        frame: CGRect,
        canvasSize: CGSize
    ) -> some View {
        let menuWidth: CGFloat = 228
        let actionRowHeight: CGFloat = 50
        let availableActions = floatingActions(for: message)
        let menuHeight = CGFloat(availableActions.count) * actionRowHeight
        let emojiWidth: CGFloat = 308
        let emojiHeight: CGFloat = 50

        let bubbleCenterX = min(max(frame.midX, (emojiWidth / 2) + 16), canvasSize.width - (emojiWidth / 2) - 16)
        let emojiOriginY = max(96, frame.minY - emojiHeight - 10)
        let menuOriginY = min(max(emojiOriginY + emojiHeight + 10, 112), canvasSize.height - menuHeight - 94)
        let rawMenuX = message.senderId == viewModel.currentUserID
            ? frame.maxX - menuWidth
            : frame.minX
        let menuOriginX = min(max(16, rawMenuX), canvasSize.width - menuWidth - 16)

        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissFloatingActions()
                }

            HStack(spacing: 14) {
                ForEach(floatingReactions, id: \.self) { emoji in
                    Button {
                        Task { await viewModel.toggleReaction(messageID: message.id, emoji: emoji) }
                        dismissFloatingActions()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 30))
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .frame(width: emojiWidth, height: emojiHeight)
            .background(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.11), lineWidth: 0.9)
            )
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 8)
            .position(x: bubbleCenterX, y: emojiOriginY + (emojiHeight / 2))
            .transition(.scale(scale: 0.92).combined(with: .opacity))

            VStack(spacing: 0) {
                ForEach(Array(availableActions.enumerated()), id: \.offset) { index, action in
                    Button {
                        handleFloatingAction(action, for: message)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: action.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 24)
                            Text(action.title)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                            Spacer()
                        }
                        .foregroundStyle(action.tint)
                        .padding(.horizontal, 16)
                        .frame(height: actionRowHeight)
                    }
                    .buttonStyle(.plain)

                    if index < availableActions.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.09))
                    }
                }
            }
            .frame(width: menuWidth)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.9)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 8)
            .position(
                x: menuOriginX + (menuWidth / 2),
                y: menuOriginY + (menuHeight / 2)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(150)
    }

    private func floatingActions(for message: Message) -> [FloatingAction] {
        [
            FloatingAction(kind: .reply, title: "Reply", icon: "arrowshape.turn.up.left", tint: .white),
            FloatingAction(kind: .forward, title: "Forward", icon: "arrowshape.turn.up.right", tint: .white),
            FloatingAction(
                kind: .star,
                title: starredMessageIDs.contains(message.id) ? "Unstar" : "Star",
                icon: starredMessageIDs.contains(message.id) ? "star.slash" : "star",
                tint: .white
            ),
            FloatingAction(kind: .edit, title: "Edit", icon: "pencil", tint: .white),
            FloatingAction(kind: .delete, title: "Delete", icon: "trash", tint: Color(red: 1, green: 0.48, blue: 0.48)),
        ]
    }

    private func handleFloatingAction(_ action: FloatingAction, for message: Message) {
        PingyHaptics.softTap()
        dismissFloatingActions()

        switch action.kind {
        case .reply:
            viewModel.setReplyTarget(message)
        case .forward:
            forwardMessage(message)
        case .star:
            toggleStar(for: message.id)
        case .edit:
            guard message.senderId == viewModel.currentUserID else {
                viewModel.showTransientNotice("You can edit only your messages.", style: .warning)
                return
            }
            let sourceText = viewModel.decryptedBody(for: message)
                ?? MessageBodyFormatter.previewText(from: message.body, fallback: "")
            let normalized = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                viewModel.showTransientNotice("Edit is available for text messages.", style: .warning)
                return
            }
            draft = normalized
            isComposerFocused = true
        case .delete:
            viewModel.deleteMessageLocally(
                messageID: message.id,
                conversationID: conversation.conversationId
            )
        }
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
        viewModel.startCall(from: conversation)
    }

    private func refreshLockState() {
        isChatLocked = ChatLockService.shared.isChatLocked(conversationID: conversation.conversationId)
        if !isChatLocked {
            unlockPasscode = ""
        }
    }

    private func unlockChat() {
        let passcode = unlockPasscode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !passcode.isEmpty else {
            viewModel.showTransientNotice("Enter chat password first.", style: .warning)
            return
        }

        guard ChatLockService.shared.verify(passcode: passcode, for: conversation.conversationId) else {
            viewModel.showTransientNotice("Incorrect chat password.", style: .error)
            return
        }

        unlockPasscode = ""
        isChatLocked = false
        PingyHaptics.success()
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

private struct ChatBottomAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatMessageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct FloatingAction {
    enum Kind {
        case reply
        case forward
        case star
        case edit
        case delete
    }

    let kind: Kind
    let title: String
    let icon: String
    let tint: Color
}

private struct SpaceParticleField: View {
    let seed: Int

    var body: some View {
        GeometryReader { proxy in
            let points = generatedPoints(count: 64)

            ZStack {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(Color.white.opacity(index % 3 == 0 ? 0.17 : 0.09))
                        .frame(width: index % 5 == 0 ? 3.2 : 2, height: index % 5 == 0 ? 3.2 : 2)
                        .position(
                            x: point.x * proxy.size.width,
                            y: point.y * proxy.size.height
                        )
                        .blur(radius: index % 5 == 0 ? 1.1 : 0)
                }
            }
            .drawingGroup(opaque: false, colorMode: .linear)
        }
        .allowsHitTesting(false)
    }

    private func generatedPoints(count: Int) -> [CGPoint] {
        var generator = SeededGenerator(seed: UInt64(abs(seed) + 1))
        return (0 ..< count).map { _ in
            CGPoint(
                x: CGFloat.random(in: 0 ... 1, using: &generator),
                y: CGFloat.random(in: 0 ... 1, using: &generator)
            )
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xA5A5A5A5A5A5A5A5 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}



