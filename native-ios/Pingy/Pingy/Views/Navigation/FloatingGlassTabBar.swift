import SwiftUI

struct FloatingGlassTabBar: View {
    @Binding var selectedTab: PingyRootTab

    let unreadCount: Int
    let compact: Bool
    let onSelect: (PingyRootTab) -> Void

    @State private var dragOffsetX: CGFloat = 0
    @State private var dragOffsetY: CGFloat = 0
    @State private var reflectionPhase = false

    var body: some View {
        GeometryReader { proxy in
            let tabs = PingyRootTab.allCases
            let contentWidth = max(1, proxy.size.width - 16)
            let slotWidth = contentWidth / CGFloat(max(tabs.count, 1))
            let selectedIndex = CGFloat(tabs.firstIndex(of: selectedTab) ?? 0)
            let baseBubbleWidth = max(48, slotWidth - 14)
            let pullAmount = max(0, min(24, -dragOffsetY))
            let bubbleWidth = baseBubbleWidth + pullAmount * 0.35
            let barHeight = (compact ? 60.0 : 70.0) + Double(pullAmount * 0.45)
            let highlightOpacity = compact ? 0.68 : 0.84

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 31, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 31, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                            .blur(radius: 0.3)
                    }
                    .overlay(alignment: .topLeading) {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(reflectionPhase ? 0.34 : 0.24),
                                Color.white.opacity(0.04),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.screen)
                        .offset(x: dragOffsetX * 0.5, y: dragOffsetY * 0.15)
                        .animation(.easeInOut(duration: 0.44), value: reflectionPhase)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 31, style: .continuous)
                            .stroke(PingyTheme.border.opacity(0.34), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.24), radius: 18, y: 10)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PingyTheme.primarySoft.opacity(highlightOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
                    )
                    .frame(width: bubbleWidth, height: compact ? 44 : 50)
                    .offset(x: 8 + selectedIndex * slotWidth + dragOffsetX * 0.06)
                    .animation(.spring(response: 0.36, dampingFraction: 0.84), value: selectedTab)
                    .animation(.spring(response: 0.3, dampingFraction: 0.82), value: pullAmount)

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        TabItem(
                            tab: tab,
                            isSelected: tab == selectedTab,
                            unreadCount: unreadCount,
                            parallaxX: dragOffsetX * 0.04,
                            onTap: {
                                guard selectedTab != tab else { return }
                                reflectionPhase.toggle()
                                onSelect(tab)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: barHeight)
            .scaleEffect(dragOffsetY < 0 ? 1 + ((-dragOffsetY) / 650) : 1)
            .rotation3DEffect(
                .degrees(Double(dragOffsetX / 12)),
                axis: (x: 0, y: 1, z: 0)
            )
            .offset(y: dragOffsetY < 0 ? dragOffsetY * 0.12 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: compact)
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        dragOffsetX = max(-34, min(34, value.translation.width))
                        dragOffsetY = max(-26, min(12, value.translation.height))
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                            dragOffsetX = 0
                            dragOffsetY = 0
                        }
                    }
            )
        }
        .frame(height: compact ? 64 : 74)
    }
}
