import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: PingyRootTab

    let unreadCount: Int
    let compact: Bool
    let onSelect: (PingyRootTab) -> Void

    @State private var dragOffsetX: CGFloat = 0
    @State private var reflectionPulse = false

    var body: some View {
        GeometryReader { proxy in
            let tabs = PingyRootTab.allCases
            let contentWidth = max(1, proxy.size.width - 16)
            let slotWidth = contentWidth / CGFloat(max(tabs.count, 1))
            let selectedIndex = CGFloat(tabs.firstIndex(of: selectedTab) ?? 0)
            let bubbleWidth = max(44, slotWidth - 14)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                            .blur(radius: 0.2)
                    }
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.clear, Color.white.opacity(0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .blendMode(.screen)
                        .opacity(reflectionPulse ? 0.72 : 0.42)
                        .offset(x: dragOffsetX * 0.45)
                        .animation(.easeInOut(duration: 0.55), value: reflectionPulse)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(PingyTheme.border.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 16, y: 10)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PingyTheme.primarySoft.opacity(selectedTab.isPrimary ? 0.96 : 0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                    )
                    .frame(width: bubbleWidth, height: compact ? 44 : 50)
                    .offset(x: 8 + selectedIndex * slotWidth + dragOffsetX * 0.06)
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: selectedTab)
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: compact)

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        TabItem(
                            tab: tab,
                            isSelected: tab == selectedTab,
                            unreadCount: unreadCount,
                            parallaxX: dragOffsetX * 0.03,
                            onTap: {
                                guard selectedTab != tab else { return }
                                reflectionPulse.toggle()
                                onSelect(tab)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: compact ? 60 : 70)
            .rotation3DEffect(.degrees(Double(dragOffsetX / 10)), axis: (x: 0, y: 1, z: 0))
            .scaleEffect(compact ? 0.96 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: compact)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        dragOffsetX = max(-36, min(36, value.translation.width))
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            dragOffsetX = 0
                        }
                    }
            )
        }
        .frame(height: compact ? 60 : 70)
    }
}
