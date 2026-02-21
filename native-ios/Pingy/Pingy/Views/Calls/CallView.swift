import SwiftUI

struct CallView: View {
    let session: CallSignalingService.CallSession
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onToggleMute: () -> Void
    let onToggleSpeaker: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack {
            PingyTheme.wallpaperFallback(for: .dark)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.32),
                    Color.black.opacity(0.56),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                AvatarView(
                    url: session.participantAvatarURL,
                    fallback: session.participantName,
                    size: 124,
                    cornerRadius: 62
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 2)
                )

                VStack(spacing: 6) {
                    Text(session.participantName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    statusLabel
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                }

                Spacer()

                if session.direction == .incoming, session.status == .ringing {
                    HStack(spacing: 26) {
                        actionButton(
                            icon: "phone.down.fill",
                            title: "Decline",
                            tint: .red,
                            action: onDecline
                        )
                        actionButton(
                            icon: "phone.fill",
                            title: "Accept",
                            tint: .green,
                            action: onAccept
                        )
                    }
                    .padding(.bottom, 44)
                } else {
                    HStack(spacing: 26) {
                        actionButton(
                            icon: session.isMuted ? "mic.slash.fill" : "mic.fill",
                            title: session.isMuted ? "Unmute" : "Mute",
                            tint: session.isMuted ? .orange : Color.white.opacity(0.16),
                            action: onToggleMute
                        )
                        actionButton(
                            icon: session.isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill",
                            title: session.isSpeakerEnabled ? "Speaker" : "Earpiece",
                            tint: session.isSpeakerEnabled ? .orange : Color.white.opacity(0.16),
                            action: onToggleSpeaker
                        )
                        actionButton(
                            icon: "phone.down.fill",
                            title: "End",
                            tint: .red,
                            action: onEnd
                        )
                    }
                    .padding(.bottom, 44)
                }
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if session.status == .connected, session.startedAt != nil {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(durationText(from: session.startedAt))
            }
        } else {
            Text(callStateText)
        }
    }

    private var callStateText: String {
        switch session.status {
        case .ringing:
            return session.direction == .incoming ? "Incoming call..." : "Ringing..."
        case .connected:
            return durationText(from: session.startedAt)
        case .declined:
            return "Declined"
        case .ended:
            return "Call ended"
        case .missed:
            return "Missed call"
        }
    }

    private func durationText(from startedAt: Date?) -> String {
        guard let startedAt else { return "Connecting..." }
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func actionButton(
        icon: String,
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(tint)
                    .clipShape(Circle())

                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .frame(minWidth: 72)
        }
        .buttonStyle(PingyPressableButtonStyle())
    }
}
