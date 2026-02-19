import AVFoundation
import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: Message
    let conversation: Conversation
    let currentUserID: String?
    let cryptoService: E2EECryptoService
    let onReply: () -> Void
    let onReact: (String) -> Void

    @State private var decryptedText: String?
    @State private var decryptionFailed = false

    private var isOwn: Bool {
        message.senderId == currentUserID
    }

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 32) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                if let reply = message.replyTo {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reply")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isOwn ? Color.white.opacity(0.85) : Color.cyan)
                        Text(reply.body?.stringValue ?? reply.mediaName ?? "Message")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(isOwn ? Color.white.opacity(0.8) : Color.primary.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background((isOwn ? Color.black.opacity(0.15) : Color.black.opacity(0.05)))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                content

                HStack(spacing: 6) {
                    Text(formatTime(message.createdAt))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isOwn ? Color.white.opacity(0.76) : Color.secondary)
                    if isOwn {
                        Image(systemName: message.seenAt != nil ? "checkmark.circle.fill" : message.deliveredAt != nil ? "checkmark.circle" : "clock")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(message.seenAt != nil ? Color.green : Color.white.opacity(0.76))
                    }
                }

                if !message.reactions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.reactions, id: \.emoji) { reaction in
                            Text("\(reaction.emoji) \(reaction.count)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(isOwn ? 0.2 : 0.9))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isOwn
                    ? LinearGradient(
                        colors: [Color(red: 0.03, green: 0.65, blue: 0.84), Color(red: 0.05, green: 0.58, blue: 0.79)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(colors: [Color.white, Color.white.opacity(0.92)], startPoint: .top, endPoint: .bottom)
            )
            .foregroundStyle(isOwn ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                    ForEach(["👍", "❤️", "😂", "😮", "😢", "🔥", "👏", "🙏"], id: \.self) { emoji in
                        Button(emoji) {
                            onReact(emoji)
                        }
                    }
                }
            }

            if !isOwn { Spacer(minLength: 32) }
        }
        .padding(.horizontal, 6)
        .task(id: message.id) {
            await decryptIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.type {
        case .text:
            Text(renderedText ?? "")
                .font(.system(size: 25, weight: .regular, design: .rounded))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 300, alignment: .leading)
        case .image:
            if let urlString = message.mediaUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 200, height: 180)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 220, height: 220)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    case .failure:
                        Text("Image unavailable")
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        case .video:
            if let urlString = message.mediaUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Open video", systemImage: "video.fill")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
            }
        case .file:
            if let urlString = message.mediaUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(message.mediaName ?? "Open file", systemImage: "doc.fill")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
            }
        case .voice:
            if let urlString = message.mediaUrl, let url = URL(string: urlString) {
                VoiceMessagePlayerView(url: url, durationMs: message.voiceDurationMs ?? 0, isOwnMessage: isOwn)
                    .frame(maxWidth: 240, alignment: .leading)
            }
        }
    }

    private var renderedText: String? {
        switch message.type {
        case .text:
            if message.isEncrypted {
                if let decryptedText {
                    return decryptedText
                }
                return decryptionFailed ? "Unable to decrypt message" : "..."
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
        guard let currentUserID else {
            return
        }
        guard let payload = encryptedPayload(from: message.body) else {
            decryptionFailed = true
            return
        }

        do {
            let peerKey = try await resolvePeerKey()
            let plain = try await cryptoService.decryptText(
                payload: payload,
                userID: currentUserID,
                peerUserID: conversation.participantId,
                peerPublicKeyJWK: peerKey
            )
            decryptedText = plain
            decryptionFailed = false
        } catch {
            decryptionFailed = true
        }
    }

    private func resolvePeerKey() async throws -> PublicKeyJWK {
        if let cached = conversation.participantPublicKeyJwk {
            return cached
        }
        throw CryptoServiceError.invalidPeerPublicKey
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
                    .background(isOwnMessage ? Color.white.opacity(0.22) : Color.black.opacity(0.06))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isOwnMessage ? Color.white.opacity(0.2) : Color.black.opacity(0.15))
                        Capsule()
                            .fill(isOwnMessage ? Color.white : Color.cyan)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)

                Text(durationText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isOwnMessage ? Color.white.opacity(0.82) : Color.secondary)
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
