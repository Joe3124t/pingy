import SwiftUI

struct FloatingGlassTabBar: View {
    @Binding var selectedTab: PingyRootTab

    let unreadCount: Int
    let compact: Bool
    let onSelect: (PingyRootTab) -> Void

    private let accent = Color(red: 0.14, green: 0.84, blue: 0.39)

    var body: some View {
        GeometryReader { proxy in
            let tabs = PingyRootTab.allCases
            let horizontalInset: CGFloat = 10
            let contentWidth = max(1, proxy.size.width - (horizontalInset * 2))
            let slotWidth = contentWidth / CGFloat(max(tabs.count, 1))
            let selectedIndex = CGFloat(tabs.firstIndex(of: selectedTab) ?? 0)
            let barHeight: CGFloat = compact ? 62 : 68
            let activeBubbleWidth = min(112, max(84, slotWidth + 24))
            let activeBubbleHeight = barHeight + 14

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
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
                            .frame(height: 22)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.01),
                                Color.clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .allowsHitTesting(false)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.26), radius: 16, y: 8)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.23, green: 0.23, blue: 0.25),
                                Color(red: 0.19, green: 0.19, blue: 0.21),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 0.9)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(accent.opacity(0.36), lineWidth: 1.2)
                            .padding(1)
                    )
                    .frame(width: activeBubbleWidth, height: activeBubbleHeight)
                    .offset(
                        x: horizontalInset + selectedIndex * slotWidth + (slotWidth - activeBubbleWidth) / 2,
                        y: -7
                    )
                    .animation(.spring(response: 0.36, dampingFraction: 0.84), value: selectedTab)
                    .shadow(color: accent.opacity(0.20), radius: 10, y: 4)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        TabItem(
                            tab: tab,
                            isSelected: tab == selectedTab,
                            unreadCount: unreadCount,
                            parallaxX: 0,
                            onTap: {
                                guard selectedTab != tab else { return }
                                onSelect(tab)
                            }
                        )
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
            .frame(height: barHeight)
        }
        .frame(height: compact ? 76 : 84)
    }
}
