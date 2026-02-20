import AVFoundation
import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: Message
    let conversation: Conversation
    let currentUserID: String?
    let cryptoService: E2EECryptoService
    let resolvePeerKey: (_ forceRefresh: Bool) async throws -> PublicKeyJWK
    let isGroupedWithPrevious: Bool
    let onReply: () -> Void
    let onReact: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var decryptedText: String?
    @State private var decryptionFailed = false
    @State private var didRetryDecryption = false
    @State private var isVisible = false

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
            .contextMenu {
                if let text = renderedText, !text.isEmpty {
                    Button {
                        UIPasteboard.general.string = text
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
        .task(id: message.id) {
            await decryptIfNeeded()
        }
        .onAppear {
            isVisible = true
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
            Text(renderedText ?? "")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(isOwn ? Color.white : PingyTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 320, alignment: .leading)

        case .image:
            if let urlString = message.mediaUrl, let url = URL(string: urlString) {
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
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    case .failure:
                        Text("Image unavailable")
                            .foregroundStyle(isOwn ? Color.white : PingyTheme.textSecondary)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

        case .video:
            if let urlString = message.mediaUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Open video", systemImage: "video.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(isOwn ? Color.white : PingyTheme.primary)
                }
            }

        case .file:
            if let urlString = message.mediaUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(message.mediaName ?? "Open file", systemImage: "doc.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(isOwn ? Color.white : PingyTheme.primary)
                }
            }

        case .voice:
            if let urlString = message.mediaUrl, let url = URL(string: urlString) {
                VoiceMessagePlayerView(url: url, durationMs: message.voiceDurationMs ?? 0, isOwnMessage: isOwn)
                    .frame(maxWidth: 240, alignment: .leading)
            }
        }
    }

    private func replyPreview(_ reply: MessageReply) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Reply")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isOwn ? Color.white.opacity(0.9) : PingyTheme.primary)
            Text(reply.body?.stringValue ?? reply.mediaName ?? "Message")
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

    private var renderedText: String? {
        switch message.type {
        case .text:
            if message.isEncrypted {
                if let decryptedText {
                    return decryptedText
                }
                return decryptionFailed ? "Message corrupted" : "Decrypting..."
            }
            return message.body?.stringValue ?? ""
        default:
            return nil
        }
    }

    private func formatTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "" }
        let output = DateFormatter()
        output.timeStyle = .short
        return output.string(from: date)
    }

    private func decryptIfNeeded() async {
        guard message.type == .text, message.isEncrypted else {
            return
        }

        didRetryDecryption = false
        decryptionFailed = false
        decryptedText = nil

        guard let currentUserID else {
            return
        }
        guard let payload = encryptedPayload(from: message.body) else {
            decryptionFailed = true
            return
        }

        do {
            let peerKey = try await resolvePeerKey(false)
            let plain = try await cryptoService.decryptText(
                payload: payload,
                userID: currentUserID,
                peerUserID: conversation.participantId,
                peerPublicKeyJWK: peerKey
            )
            decryptedText = plain
            decryptionFailed = false
        } catch {
            if !didRetryDecryption {
                didRetryDecryption = true
                AppLogger.debug("Decrypt failed for message \(message.id). Refreshing conversation key once.")
                await cryptoService.invalidateConversationKey(userID: currentUserID, peerUserID: conversation.participantId)

                do {
                    let peerKey = try await resolvePeerKey(true)
                    let plain = try await cryptoService.decryptText(
                        payload: payload,
                        userID: currentUserID,
                        peerUserID: conversation.participantId,
                        peerPublicKeyJWK: peerKey
                    )
                    decryptedText = plain
                    decryptionFailed = false
                    return
                } catch {
                    AppLogger.error("Decrypt retry failed for message \(message.id): \(error.localizedDescription)")
                    decryptionFailed = true
                    return
                }
            }

            AppLogger.error("Decrypt failed for message \(message.id): \(error.localizedDescription)")
            decryptionFailed = true
        }
    }

    private func encryptedPayload(from jsonValue: JSONValue?) -> EncryptedPayload? {
        guard let jsonValue else { return nil }
        if let object = jsonValue.objectValue {
            guard
                let v = object["v"]?.intValue,
                let alg = object["alg"]?.stringValue,
                let iv = object["iv"]?.stringValue,
                let ciphertext = object["ciphertext"]?.stringValue
            else {
                return nil
            }
            return EncryptedPayload(v: v, alg: alg, iv: iv, ciphertext: ciphertext)
        }

        if let stringValue = jsonValue.stringValue,
           let data = stringValue.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(EncryptedPayload.self, from: data)
        {
            return decoded
        }

        return nil
    }
}

private extension JSONValue {
    var intValue: Int? {
        if case .number(let value) = self {
            return Int(value)
        }
        return nil
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
