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
                    .font(.system(size: compact ? 22 : 29, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: compact ? 10 : 11, weight: .medium, design: .rounded))
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
                    .frame(width: compact ? 32 : 36, height: compact ? 32 : 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isStatusActive ? 0.35 : 0.2), lineWidth: 1)
                    )
                    .shadow(color: PingyTheme.primary.opacity(isStatusActive ? 0.28 : 0.08), radius: 8, y: 3)
            }
            .buttonStyle(PingyPressableButtonStyle())
            .accessibilityLabel(String(localized: "Status"))
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 6 : 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(compact ? 0.08 : 0.12), radius: compact ? 8 : 11, y: compact ? 2 : 4)
        .scaleEffect(compact ? 0.985 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: compact)
    }
}
