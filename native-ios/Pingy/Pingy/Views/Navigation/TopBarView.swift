import SwiftUI

struct TopBarView: View {
    let title: String
    let subtitle: String?
    let compact: Bool
    let isStatusActive: Bool
    let onStatusTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: compact ? 24 : 31, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: compact ? 11 : 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 0)

            Button {
                onStatusTap()
            } label: {
                Image(systemName: "circle.dashed.inset.filled")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isStatusActive ? PingyTheme.primaryStrong : PingyTheme.textPrimary)
                    .frame(width: compact ? 34 : 38, height: compact ? 34 : 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isStatusActive ? 0.35 : 0.2), lineWidth: 1)
                    )
                    .shadow(color: PingyTheme.primary.opacity(isStatusActive ? 0.32 : 0.12), radius: 10, y: 5)
            }
            .buttonStyle(PingyPressableButtonStyle())
            .accessibilityLabel("Status")
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 8 : 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.3), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 22)
            .blendMode(.screen)
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                .stroke(PingyTheme.border.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(compact ? 0.14 : 0.18), radius: compact ? 10 : 14, y: compact ? 5 : 8)
        .scaleEffect(compact ? 0.975 : 1.0)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: compact)
    }
}
