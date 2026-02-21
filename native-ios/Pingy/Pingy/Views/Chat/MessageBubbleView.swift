import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: Message
    let conversation: Conversation
    let currentUserID: String?
    let isGroupedWithPrevious: Bool
    let onReply: () -> Void
    let onReact: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var isVisible = false
    @GestureState private var swipeOffsetX: CGFloat = 0
    @State private var selectedImageURL: URL?
    @State private var selectedVideoURL: URL?

    private var isOwn: Bool {
        message.senderId == currentUserID
    }

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 36) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                if let reply = message.replyTo {
                    replyPreview(reply)
                }

                content

                HStack(spacing: 6) {
                    Text(formatTime(message.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(isOwn ? Color.white.opacity(0.92) : PingyTheme.textSecondary)

                    if isOwn {
                        Image(systemName: statusSymbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                }

                if !message.reactions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.reactions, id: \.emoji) { reaction in
                            Text("\(reaction.emoji) \(reaction.count)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isOwn ? Color.white.opacity(0.22) : PingyTheme.reactionChipBackground)
                                .foregroundStyle(isOwn ? Color.white : PingyTheme.textPrimary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: PingyRadius.bubble, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PingyRadius.bubble, style: .continuous)
                    .stroke(isOwn ? Color.clear : PingyTheme.border, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if swipeOffsetX > 24 {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PingyTheme.primaryStrong)
                        .padding(.leading, 8)
                        .transition(.opacity)
                }
            }
            .offset(x: swipeOffsetX * 0.45)
            .onTapGesture(count: 2) {
                PingyHaptics.softTap()
                onReact("\u{2764}\u{FE0F}")
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 14)
                    .updating($swipeOffsetX) { value, state, _ in
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            state = 0
                            return
                        }
                        state = max(0, min(90, value.translation.width))
                    }
                    .onEnded { value in
                        guard value.translation.width > 70 else { return }
                        PingyHaptics.softTap()
                        onReply()
                    }
            )
            .contextMenu {
                if !renderedText.isEmpty {
                    Button {
                        UIPasteboard.general.string = renderedText
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

                Button {
                    onReply()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }

                Menu("React") {
                    ForEach(reactionEmojis, id: \.self) { emoji in
                        Button(emoji) {
                            onReact(emoji)
                        }
                    }
                }
            }

            if !isOwn { Spacer(minLength: 36) }
        }
        .padding(.horizontal, 6)
        .padding(.top, isGroupedWithPrevious ? 1 : 8)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 12)
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: isVisible)
        .onAppear {
            isVisible = true
        }
        .sheet(isPresented: imageSheetPresentedBinding) {
            if let selectedImageURL {
                ChatImagePreviewSheet(url: selectedImageURL)
            }
        }
        .sheet(isPresented: videoSheetPresentedBinding) {
            if let selectedVideoURL {
                ChatVideoPreviewSheet(url: selectedVideoURL)
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if isOwn {
            return AnyShapeStyle(LinearGradient(
                colors: [PingyTheme.sentBubbleStart, PingyTheme.sentBubbleEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        return AnyShapeStyle(PingyTheme.receivedBubble)
    }

    private var statusSymbol: String {
        if message.seenAt != nil {
            return "checkmark.circle.fill"
        }
        if message.deliveredAt != nil {
            return "checkmark.circle"
        }
        return "clock"
    }

    private var statusColor: Color {
        message.seenAt != nil ? PingyTheme.success : Color.white.opacity(0.92)
    }

    private var reactionEmojis: [String] {
        [
            "\u{1F44D}",
            "\u{2764}\u{FE0F}",
            "\u{1F602}",
            "\u{1F62E}",
            "\u{1F622}",
            "\u{1F525}",
            "\u{1F44F}",
            "\u{1F64F}",
        ]
    }

    @ViewBuilder
    private var content: some View {
        switch message.type {
        case .text:
            Text(renderedText)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(isOwn ? Color.white : PingyTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 320, alignment: .leading)

        case .image:
            if let url = MediaURLResolver.resolve(message.mediaUrl) {
                Button {
                    selectedImageURL = url
                } label: {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().frame(width: 210, height: 180)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 230, height: 220)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        case .failure:
                            Text("Image unavailable")
                                .foregroundStyle(isOwn ? Color.white : PingyTheme.textSecondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .buttonStyle(.plain)
            }

        case .video:
            if let url = MediaURLResolver.resolve(message.mediaUrl) {
                Button {
                    selectedVideoURL = url
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(isOwn ? Color.white : PingyTheme.primaryStrong)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.mediaName ?? "Video")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(isOwn ? Color.white : PingyTheme.textPrimary)
                                .lineLimit(1)
                            Text("Tap to open")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(isOwn ? Color.white.opacity(0.85) : PingyTheme.textSecondary)
                        }
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }

        case .file:
            if let url = MediaURLResolver.resolve(message.mediaUrl) {
                Link(destination: url) {
                    Label(message.mediaName ?? "Open file", systemImage: "doc.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(isOwn ? Color.white : PingyTheme.primary)
                }
            }

        case .voice:
            if let url = MediaURLResolver.resolve(message.mediaUrl) {
                VoiceMessagePlayerView(url: url, durationMs: message.voiceDurationMs ?? 0, isOwnMessage: isOwn)
                    .frame(maxWidth: 240, alignment: .leading)
            }
        }
    }

    private func replyPreview(_ reply: MessageReply) -> some View {
        let senderName = (reply.senderUsername?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (reply.senderUsername ?? "Unknown")
            : "Unknown"
        let preview = MessageBodyFormatter.previewText(from: reply.body, fallback: reply.mediaName ?? "Message")

        return VStack(alignment: .leading, spacing: 2) {
            Text("From \(senderName)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isOwn ? Color.white.opacity(0.9) : PingyTheme.primary)
            Text(preview)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(isOwn ? Color.white.opacity(0.83) : PingyTheme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isOwn
                ? Color.black.opacity(colorScheme == .dark ? 0.3 : 0.15)
                : PingyTheme.surfaceElevated
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var renderedText: String {
        MessageBodyFormatter.previewText(from: message.body, fallback: "Message")
    }

    private func formatTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "" }
        let output = DateFormatter()
        output.timeStyle = .short
        return output.string(from: date)
    }

    private var imageSheetPresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedImageURL != nil },
            set: { isPresented in
                if !isPresented {
                    selectedImageURL = nil
                }
            }
        )
    }

    private var videoSheetPresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedVideoURL != nil },
            set: { isPresented in
                if !isPresented {
                    selectedVideoURL = nil
                }
            }
        )
    }
}

private struct ChatImagePreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        Text("Image unavailable")
                            .foregroundStyle(.white.opacity(0.88))
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ChatVideoPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .onAppear {
                if player == nil {
                    player = AVPlayer(url: url)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private final class VoiceAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var didFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        didFinish?()
    }
}

struct VoiceMessagePlayerView: View {
    let url: URL
    let durationMs: Int
    let isOwnMessage: Bool

    @State private var audioPlayer: AVAudioPlayer?
    @State private var delegateBox = VoiceAudioPlayerDelegate()
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(isOwnMessage ? Color.white.opacity(0.22) : PingyTheme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(PingyPressableButtonStyle())

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isOwnMessage ? Color.white.opacity(0.24) : PingyTheme.border.opacity(0.6))
                        Capsule()
                            .fill(isOwnMessage ? Color.white : PingyTheme.primaryStrong)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)

                Text(durationText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isOwnMessage ? Color.white.opacity(0.9) : PingyTheme.textSecondary)
            }
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private var durationText: String {
        let totalSeconds = max(0, durationMs / 1000)
        let minute = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minute, seconds)
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let player = try AVAudioPlayer(data: data)
            delegateBox.didFinish = {
                isPlaying = false
                progress = 0
                timer?.invalidate()
                timer = nil
            }
            player.delegate = delegateBox
            player.play()
            audioPlayer = player
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                guard let audioPlayer, audioPlayer.duration > 0 else { return }
                progress = min(1, audioPlayer.currentTime / audioPlayer.duration)
            }
        } catch {
            AppLogger.error("Voice playback failed: \(error.localizedDescription)")
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        progress = 0
        timer?.invalidate()
        timer = nil
    }
}
