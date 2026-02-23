import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct StatusTabView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @StateObject private var viewModel: StatusViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var statusMediaItem: PhotosPickerItem?
    @State private var isTextComposerPresented = false
    @State private var textStatus = ""
    @State private var textStatusColorHex = "#0A7E8C"
    @State private var selectedStory: StatusStory?
    @State private var statusRefreshTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    init(messengerViewModel: MessengerViewModel, statusService: StatusService) {
        self.messengerViewModel = messengerViewModel
        _viewModel = StateObject(wrappedValue: StatusViewModel(service: statusService))
    }

    private var currentUserID: String {
        messengerViewModel.currentUserID ?? "unknown-user"
    }

    private var currentUserName: String {
        messengerViewModel.currentUserSettings?.username ?? "You"
    }

    private var currentUserAvatar: String? {
        messengerViewModel.currentUserSettings?.avatarUrl
    }

    private var myStories: [StatusStory] {
        viewModel.stories.filter { $0.ownerUserID == currentUserID }
    }

    private var recentStories: [StatusStory] {
        viewModel.stories.filter { $0.ownerUserID != currentUserID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                composerCard

                if !myStories.isEmpty {
                    sectionCard(title: "My status") {
                        ForEach(myStories) { story in
                            storyRow(story, mine: true)
                        }
                    }
                }

                sectionCard(title: "Recent updates") {
                    if recentStories.isEmpty {
                        Text("No recent status updates yet.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(PingyTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(recentStories) { story in
                            storyRow(story, mine: false)
                        }
                    }
                }
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("Status")
        .onAppear {
            Task { await viewModel.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pingyStatusUpdated)) { _ in
            Task { await viewModel.reload() }
        }
        .onReceive(statusRefreshTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await viewModel.reload() }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { await viewModel.reload() }
        }
        .refreshable {
            await viewModel.reload()
        }
        .onChange(of: statusMediaItem) { newValue in
            guard let newValue else { return }
            Task {
                let contentType = newValue.supportedContentTypes.first
                let isVideo = contentType?.conforms(to: .movie) ?? false
                let fileExtension = contentType?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")

                if isVideo,
                   let mediaURL = try? await newValue.loadTransferable(type: URL.self)
                {
                    let duration = AVURLAsset(url: mediaURL).duration.seconds
                    if duration > 30 {
                        viewModel.errorMessage = "Video status must be 30 seconds or less."
                        statusMediaItem = nil
                        return
                    }
                }

                guard let mediaData = try? await newValue.loadTransferable(type: Data.self) else {
                    viewModel.errorMessage = "Couldn't read selected media."
                    statusMediaItem = nil
                    return
                }

                await viewModel.postMediaStory(
                    ownerUserID: currentUserID,
                    ownerName: currentUserName,
                    ownerAvatarURL: currentUserAvatar,
                    data: mediaData,
                    fileExtension: fileExtension,
                    contentType: isVideo ? .video : .image
                )

                statusMediaItem = nil
            }
        }
        .sheet(isPresented: $isTextComposerPresented) {
            NavigationStack {
                textComposer
            }
        }
        .fullScreenCover(item: $selectedStory) { story in
            StatusStoryViewer(
                story: story,
                isOwnStory: story.ownerUserID == currentUserID,
                onClose: {
                    selectedStory = nil
                },
                onDelete: {
                    Task {
                        await viewModel.deleteStory(story.id)
                        selectedStory = nil
                    }
                }
            )
        }
        .alert(
            "Status",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Create status")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Picker("Privacy", selection: $viewModel.selectedPrivacy) {
                ForEach(StatusPrivacy.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button {
                    isTextComposerPresented = true
                } label: {
                    Label("Text", systemImage: "text.bubble")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(PingyTheme.primary)

                PhotosPicker(selection: $statusMediaItem, matching: .any(of: [.images, .videos])) {
                    Label("Photo/Video", systemImage: "camera.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.bordered)
            }
        }
        .pingyCard()
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            content()
        }
        .pingyCard()
    }

    private func storyRow(_ story: StatusStory, mine: Bool) -> some View {
        Button {
            if !mine {
                Task {
                    await viewModel.markViewed(storyID: story.id, viewerID: currentUserID, viewerName: currentUserName)
                }
            }
            selectedStory = story
        } label: {
            HStack(spacing: PingySpacing.sm) {
                ZStack {
                    AvatarView(
                        url: story.ownerAvatarURL,
                        fallback: story.ownerName,
                        size: 52,
                        cornerRadius: 26
                    )
                    Circle()
                        .stroke(PingyTheme.primary, lineWidth: 2.5)
                        .frame(width: 58, height: 58)
                        .opacity(0.9)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(mine ? "My status" : story.ownerName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                    Text(storyTimestamp(story.createdAt))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                }
                Spacer()
                if mine {
                    Text("\(story.viewers.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PingyTheme.surfaceElevated)
                        .clipShape(Capsule())
                        .foregroundStyle(PingyTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var textComposer: some View {
        VStack(spacing: PingySpacing.md) {
            TextEditor(text: $textStatus)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 220)
                .background(Color(hex: textStatusColorHex).opacity(colorScheme == .dark ? 0.45 : 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 8) {
                ForEach(["#0A7E8C", "#1D4ED8", "#8B5CF6", "#EA580C", "#4D7C0F"], id: \.self) { color in
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle().stroke(Color.white.opacity(textStatusColorHex == color ? 1 : 0), lineWidth: 2)
                        )
                        .onTapGesture {
                            textStatusColorHex = color
                        }
                }
                Spacer()
            }

            Button {
                Task {
                    await viewModel.postTextStory(
                        ownerUserID: currentUserID,
                        ownerName: currentUserName,
                        ownerAvatarURL: currentUserAvatar,
                        text: textStatus,
                        backgroundHex: textStatusColorHex
                    )
                    textStatus = ""
                    isTextComposerPresented = false
                }
            } label: {
                Text("Post status")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(PingyTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
            .disabled(textStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving)

            Spacer()
        }
        .padding(PingySpacing.md)
        .navigationTitle("Text status")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    isTextComposerPresented = false
                }
            }
        }
        .background(PingyTheme.background.ignoresSafeArea())
    }

    private func storyTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct StatusStoryViewer: View {
    let story: StatusStory
    let isOwnStory: Bool
    let onClose: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            storyBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    AvatarView(url: story.ownerAvatarURL, fallback: story.ownerName, size: 34, cornerRadius: 17)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(story.ownerName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(dateLabel)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    Spacer()
                    if isOwnStory {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                    }
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)

                Spacer()

                if isOwnStory {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Viewers")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                        if story.viewers.isEmpty {
                            Text("No viewers yet")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                        } else {
                            ForEach(story.viewers.prefix(5)) { viewer in
                                Text("\(viewer.name) - \(relativeTime(viewer.viewedAt))")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private var storyBackground: some View {
        switch story.contentType {
        case .text:
            Color(hex: story.backgroundHex ?? "#0A7E8C")
                .overlay(
                    Text(story.text ?? "")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(24)
                )
        case .image:
            if let url = MediaURLResolver.resolve(story.mediaURL) {
                ZStack {
                    Color.black
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .failure:
                            Text("Status image unavailable")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            } else {
                Color.black
            }
        case .video:
            if let url = MediaURLResolver.resolve(story.mediaURL) {
                StatusVideoPlayer(url: url)
            } else {
                Color.black
            }
        }
    }

    private var dateLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: story.createdAt, relativeTo: Date())
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct StatusVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear {
            if player == nil {
                player = AVPlayer(url: url)
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        guard clean.count == 6, let value = Int(clean, radix: 16) else {
            self = PingyTheme.primary
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}
