import SwiftUI

struct FloatingGlassTabBar: View {
    @Binding var selectedTab: PingyRootTab

    let unreadCount: Int
    let compact: Bool
    let onSelect: (PingyRootTab) -> Void

    @State private var horizontalTilt: CGFloat = 0
    @State private var reflectionShift: CGFloat = 0
    @State private var glowPulse = false

    private let accent = Color(red: 0.14, green: 0.84, blue: 0.39)
    private let chatsAccent = Color(red: 0.13, green: 0.86, blue: 0.78)

    var body: some View {
        GeometryReader { proxy in
            let tabs = PingyRootTab.allCases
            let horizontalInset: CGFloat = 10
            let contentWidth = max(1, proxy.size.width - (horizontalInset * 2))
            let slotWidth = contentWidth / CGFloat(max(tabs.count, 1))
            let selectedIndex = CGFloat(tabs.firstIndex(of: selectedTab) ?? 0)
            let barHeight: CGFloat = compact ? 62 : 68
            let activeBubbleWidth = min(120, max(86, slotWidth + 24))
            let activeBubbleHeight = barHeight + 16

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
                        .offset(x: reflectionShift)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .allowsHitTesting(false)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.26), radius: 16, y: 8)
                    .rotation3DEffect(
                        .degrees(Double(horizontalTilt * 4)),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.8
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.84), value: horizontalTilt)

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

                if selectedTab == .chats {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(chatsAccent.opacity(glowPulse ? 0.55 : 0.28), lineWidth: 1.2)
                        .frame(width: activeBubbleWidth + 4, height: activeBubbleHeight + 4)
                        .offset(
                            x: horizontalInset + selectedIndex * slotWidth + (slotWidth - activeBubbleWidth) / 2 - 2,
                            y: -9
                        )
                        .shadow(color: chatsAccent.opacity(glowPulse ? 0.32 : 0.18), radius: glowPulse ? 16 : 11, y: 6)
                        .allowsHitTesting(false)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                                glowPulse = true
                            }
                        }
                }

                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        TabItem(
                            tab: tab,
                            isSelected: tab == selectedTab,
                            unreadCount: unreadCount,
                            parallaxX: horizontalTilt * (tab == .chats ? 1.7 : 1.2),
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
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let normalized = max(-1, min(1, value.translation.width / 90))
                        horizontalTilt = normalized
                        reflectionShift = normalized * 26
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                            horizontalTilt = 0
                            reflectionShift = 0
                        }
                    }
            )
        }
        .frame(height: compact ? 76 : 84)
    }
}
