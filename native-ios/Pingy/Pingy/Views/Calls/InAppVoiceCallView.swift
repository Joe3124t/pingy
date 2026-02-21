import SwiftUI

enum InAppCallStatus: String, Equatable {
    case ringing
    case connected
    case declined
    case missed
    case ended
}

struct InAppCallSession: Identifiable, Equatable {
    let id: String
    let conversationId: String
    let participantId: String
    let participantName: String
    let participantAvatarURL: String?
    var status: InAppCallStatus
    var startedAt: Date?
    var isMuted: Bool
    var isSpeakerEnabled: Bool
}

struct InAppVoiceCallView: View {
    let session: InAppCallSession
    let onToggleMute: () -> Void
    let onToggleSpeaker: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack {
            PingyTheme.wallpaperFallback(for: .dark)
                .ignoresSafeArea()

            Color.black.opacity(0.46)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                AvatarView(
                    url: session.participantAvatarURL,
                    fallback: session.participantName,
                    size: 118,
                    cornerRadius: 59
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 2)
                )

                VStack(spacing: 6) {
                    Text(session.participantName)
                        .font(.system(size: 33, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)

                    callStatusView
                }

                Spacer()

                HStack(spacing: 28) {
                    callControlButton(
                        icon: session.isMuted ? "mic.slash.fill" : "mic.fill",
                        label: session.isMuted ? "Unmute" : "Mute",
                        tint: session.isMuted ? Color.orange : Color.white.opacity(0.15),
                        action: onToggleMute
                    )

                    callControlButton(
                        icon: session.isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill",
                        label: session.isSpeakerEnabled ? "Speaker" : "Earpiece",
                        tint: session.isSpeakerEnabled ? Color.orange : Color.white.opacity(0.15),
                        action: onToggleSpeaker
                    )

                    callControlButton(
                        icon: "phone.down.fill",
                        label: "End",
                        tint: Color.red,
                        action: onEnd
                    )
                }
                .padding(.bottom, 42)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var callStatusView: some View {
        if session.status == .connected, session.startedAt != nil {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(elapsedDurationText)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
        } else {
            Text(callStatusText)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }

    private var callStatusText: String {
        switch session.status {
        case .ringing:
            return "Ringing..."
        case .connected:
            return elapsedDurationText
        case .declined:
            return "Declined"
        case .missed:
            return "Missed call"
        case .ended:
            return "Call ended"
        }
    }

    private var elapsedDurationText: String {
        guard let startedAt = session.startedAt else {
            return "Connecting..."
        }

        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func callControlButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(tint)
                    .clipShape(Circle())
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .frame(minWidth: 70)
        }
        .buttonStyle(PingyPressableButtonStyle())
    }
}
