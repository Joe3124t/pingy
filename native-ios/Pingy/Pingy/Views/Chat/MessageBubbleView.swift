import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: Message
    let conversation: Conversation
    let currentUserID: String?
    let isGroupedWithPrevious: Bool
    let decryptedText: String?
    let uploadProgress: Double?
    let canRetryUpload: Bool
    let outgoingState: OutgoingMessageState?
    let canRetryText: Bool
    let onReply: () -> Void
    let onReact: (String) -> Void
    let onRetryUpload: () -> Void
    let onRetryText: () -> Void
    let onOpenImage: ((Message, URL) -> Void)?
    let onLongPress: (() -> Void)?
    let searchHighlightRanges: [NSRange]
    let isStarred: Bool
    let onForward: (() -> Void)?
    let onToggleStar: (() -> Void)?
    let onDeleteForMe: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var appLayoutDirection

    @State private var isVisible = false
    @GestureState private var swipeOffsetX: CGFloat = 0
    @State private var selectedImageURL: URL?
    @State private var selectedVideoURL: URL?

    private let bubbleCornerRadius: CGFloat = 22
    private let bubbleTail = CGSize(width: 10, height: 8)

    private var isOwn: Bool {
        message.senderId == currentUserID
    }

    private var isLocalPendingMedia: Bool {
        isOwn && message.id.hasPrefix("local-") && (message.type == .image || message.type == .video)
    }

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 36) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 6) {
                if let reply = message.replyTo {
                    replyPreview(reply)
                }

                content

                HStack(spacing: 6) {
                    Text(formatTime(message.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(isOwn ? Color.white.opacity(0.92) : PingyTheme.textSecondary)

                    if isOwn, let outgoingState {
                        messageStateIndicator(state: outgoingState)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                GlassMessageBubbleShape(
                    cornerRadius: bubbleCornerRadius,
                    tailSize: bubbleTail,
                    isOwn: isOwn
                )
                .fill(.ultraThinMaterial)
            }
            .overlay {
                GlassMessageBubbleShape(
                    cornerRadius: bubbleCornerRadius,
                    tailSize: bubbleTail,
                    isOwn: isOwn
                )
                .fill(bubbleTint)
            }
            .overlay(
                GlassMessageBubbleShape(
                    cornerRadius: bubbleCornerRadius,
                    tailSize: bubbleTail,
                    isOwn: isOwn
                )
                .stroke(Color.white.opacity(0.10), lineWidth: 0.9)
            )
            .overlay(alignment: .top) {
                GlassMessageBubbleShape(
                    cornerRadius: bubbleCornerRadius,
                    tailSize: bubbleTail,
                    isOwn: isOwn
                )
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .padding(.horizontal, 1)
                .padding(.top, 1)
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
            .onLongPressGesture(minimumDuration: 0.26) {
                PingyHaptics.softTap()
                onLongPress?()
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

    private var bubbleTint: some ShapeStyle {
        if isOwn {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.17, green: 0.66, blue: 0.75).opacity(0.66),
                    Color(red: 0.10, green: 0.36, blue: 0.54).opacity(0.62),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.54),
                    Color(red: 0.08, green: 0.11, blue: 0.18).opacity(0.50),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private func messageStateIndicator(state: OutgoingMessageState) -> some View {
        switch state {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
        case .delivered:
            HStack(spacing: 1) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.92))
        case .read:
            HStack(spacing: 1) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(red: 0.68, green: 0.93, blue: 0.76))
        case .failed:
            Button {
                PingyHaptics.softTap()
                onRetryText()
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle((canRetryText ? Color.red : Color.orange).opacity(0.96))
            }
            .buttonStyle(.plain)
        }
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
            Text(linkifiedAttributedText(resolvedText, highlightRanges: searchHighlightRanges))
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(isOwn ? Color.white : PingyTheme.textPrimary)
                .tint(isOwn ? Color.white : PingyTheme.primaryStrong)
                .multilineTextAlignment(textAlignment(for: resolvedText))
                .frame(maxWidth: 320, alignment: frameAlignment(for: resolvedText))
                .environment(\.layoutDirection, inferredLayoutDirection(for: resolvedText))

        case .image:
            if let url = MediaURLResolver.resolve(message.mediaUrl) {
                Button {
                    if let onOpenImage {
                        onOpenImage(message, url)
                    } else {
                        selectedImageURL = url
                    }
                } label: {
                    ZStack {
                        CachedRemoteImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 230, height: 220)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        } placeholder: {
                            ProgressView()
                                .frame(width: 210, height: 180)
                                .tint(isOwn ? .white : PingyTheme.primaryStrong)
                        } failure: {
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(isOwn ? Color.white : PingyTheme.textSecondary)
                                if canRetryUpload {
                                    Button("Retry") {
                                        onRetryUpload()
                                    }
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(isOwn ? Color.white : PingyTheme.primaryStrong)
                                } else {
                                    Text("Tap to retry later")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(isOwn ? Color.white.opacity(0.88) : PingyTheme.textSecondary)
                                }
                            }
                            .frame(width: 210, height: 120)
                        }

                        if isLocalPendingMedia {
                            mediaUploadOverlay
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
                .overlay(alignment: .center) {
                    if isLocalPendingMedia {
                        mediaUploadOverlay
                    }
                }
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
        let preview = MessageBodyFormatter.previewText(
            from: reply.body,
            fallback: MessageBodyFormatter.fallbackLabel(for: reply.type, mediaName: reply.mediaName)
        )

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
        MessageBodyFormatter.previewText(
            from: message.body,
            fallback: message.type == .text
                ? ""
                : MessageBodyFormatter.fallbackLabel(for: message.type, mediaName: message.mediaName)
        )
    }

    private var resolvedText: String {
        let normalized = decryptedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plain = normalized.isEmpty ? renderedText : normalized
        if plain.isEmpty, message.type == .text {
            return "..."
        }
        return plain
    }

    private func formatTime(_ iso: String) -> String {
        if let date = parseMessageDate(iso) {
            return Self.timeFormatter.string(from: date)
        }

        if let fallbackRange = iso.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) {
            return String(iso[fallbackRange])
        }

        return Self.timeFormatter.string(from: Date())
    }

    private func parseMessageDate(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let date = Self.isoFormatterWithFractional.date(from: value) {
            return date
        }

        if let date = Self.isoFormatter.date(from: value) {
            return date
        }

        if let date = Self.serverDateFormatter.date(from: value) {
            return date
        }

        if let date = Self.serverDateWithTimeZoneFormatter.date(from: value) {
            return date
        }

        let normalized = value.replacingOccurrences(of: " ", with: "T")
        if let date = Self.isoFormatterWithFractional.date(from: normalized) {
            return date
        }
        if let date = Self.isoFormatter.date(from: normalized) {
            return date
        }

        return nil
    }

    private func inferredLayoutDirection(for text: String) -> LayoutDirection {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return appLayoutDirection }

        var rtlCount = 0
        var ltrCount = 0

        for scalar in trimmed.unicodeScalars {
            if isRTLScalar(scalar) {
                rtlCount += 1
            } else if scalar.properties.isAlphabetic {
                ltrCount += 1
            }
        }

        if rtlCount > ltrCount {
            return .rightToLeft
        }
        if ltrCount > rtlCount {
            return .leftToRight
        }

        return appLayoutDirection
    }

    private func textAlignment(for text: String) -> TextAlignment {
        inferredLayoutDirection(for: text) == .rightToLeft ? .trailing : .leading
    }

    private func frameAlignment(for text: String) -> Alignment {
        inferredLayoutDirection(for: text) == .rightToLeft ? .trailing : .leading
    }

    private func isRTLScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0590 ... 0x08FF,
             0xFB1D ... 0xFDFF,
             0xFE70 ... 0xFEFF,
             0x1EE00 ... 0x1EEFF:
            return true
        default:
            return false
        }
    }

    private func linkifiedAttributedText(_ text: String, highlightRanges: [NSRange]) -> AttributedString {
        let mutable = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: mutable.length)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.matches(in: text, options: [], range: fullRange).forEach { match in
                guard let url = match.url else { return }
                mutable.addAttribute(.link, value: url, range: match.range)
            }
        }

        let domainPattern = #"\b((?:www\.)?[A-Za-z0-9.-]+\.[A-Za-z]{2,})(/[^\s]*)?"#
        if let regex = try? NSRegularExpression(pattern: domainPattern, options: []) {
            regex.matches(in: text, options: [], range: fullRange).forEach { match in
                guard let range = Range(match.range, in: text) else { return }
                let candidate = String(text[range])
                let lowered = candidate.lowercased()
                guard !lowered.hasPrefix("http://"),
                      !lowered.hasPrefix("https://"),
                      let url = URL(string: "https://\(candidate)")
                else {
                    return
                }
                mutable.addAttribute(.link, value: url, range: match.range)
            }
        }

        let highlightColor = UIColor(PingyTheme.primaryStrong).withAlphaComponent(colorScheme == .dark ? 0.32 : 0.22)
        for range in highlightRanges {
            guard range.location != NSNotFound, range.length > 0 else { continue }
            guard range.location + range.length <= mutable.length else { continue }
            mutable.addAttribute(.backgroundColor, value: highlightColor, range: range)
        }

        return AttributedString(mutable)
    }

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let serverDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let serverDateWithTimeZoneFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeStyle = .short
        return formatter
    }()

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

    @ViewBuilder
    private var mediaUploadOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.35))

            if canRetryUpload {
                Button {
                    PingyHaptics.softTap()
                    onRetryUpload()
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                }
                .buttonStyle(PingyPressableButtonStyle())
            } else {
                VStack(spacing: 6) {
                    ProgressView(value: uploadProgress ?? 0.18, total: 1)
                        .tint(.white)
                        .frame(width: 120)
                    Text(uploadPercentText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(width: message.type == .image ? 230 : 220, height: message.type == .image ? 220 : 80)
    }

    private var uploadPercentText: String {
        let progress = max(0, min(1, uploadProgress ?? 0))
        return "\(Int((progress * 100).rounded()))%"
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
                        ZoomableImageView(image: image)
                    case .failure:
                        Text("Couldn't load image")
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

private struct GlassMessageBubbleShape: Shape {
    let cornerRadius: CGFloat
    let tailSize: CGSize
    let isOwn: Bool

    func path(in rect: CGRect) -> Path {
        let tailHeight = max(6, tailSize.height)
        let tailWidth = max(8, tailSize.width)
        let bodyRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(1, rect.height - tailHeight)
        )

        var path = Path()
        path.addRoundedRect(
            in: bodyRect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )

        let baseY = bodyRect.maxY - 2

        if isOwn {
            let startX = bodyRect.maxX - cornerRadius * 0.55
            path.move(to: CGPoint(x: startX, y: baseY))
            path.addCurve(
                to: CGPoint(x: startX + tailWidth, y: baseY + tailHeight * 0.46),
                control1: CGPoint(x: startX + tailWidth * 0.28, y: baseY + 1),
                control2: CGPoint(x: startX + tailWidth * 0.86, y: baseY + tailHeight * 0.22)
            )
            path.addCurve(
                to: CGPoint(x: startX + tailWidth * 0.06, y: baseY + tailHeight * 0.12),
                control1: CGPoint(x: startX + tailWidth * 0.68, y: baseY + tailHeight * 0.9),
                control2: CGPoint(x: startX + tailWidth * 0.26, y: baseY + tailHeight * 0.46)
            )
            path.closeSubpath()
        } else {
            let startX = bodyRect.minX + cornerRadius * 0.55
            path.move(to: CGPoint(x: startX, y: baseY))
            path.addCurve(
                to: CGPoint(x: startX - tailWidth, y: baseY + tailHeight * 0.46),
                control1: CGPoint(x: startX - tailWidth * 0.28, y: baseY + 1),
                control2: CGPoint(x: startX - tailWidth * 0.86, y: baseY + tailHeight * 0.22)
            )
            path.addCurve(
                to: CGPoint(x: startX - tailWidth * 0.06, y: baseY + tailHeight * 0.12),
                control1: CGPoint(x: startX - tailWidth * 0.68, y: baseY + tailHeight * 0.9),
                control2: CGPoint(x: startX - tailWidth * 0.26, y: baseY + tailHeight * 0.46)
            )
            path.closeSubpath()
        }

        return path
    }
}
