import SwiftUI

private enum PingyRootTab: String, CaseIterable, Identifiable {
    case chats
    case status
    case calls
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats:
            return "Chats"
        case .status:
            return "Status"
        case .calls:
            return "Calls"
        case .settings:
            return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .chats:
            return "bubble.left.and.bubble.right.fill"
        case .status:
            return "circle.dashed.inset.filled"
        case .calls:
            return "phone.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

struct PingyTabShellView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var themeManager: ThemeManager

    @State private var selectedTab: PingyRootTab = .chats

    var body: some View {
        TabView(selection: $selectedTab) {
            MessengerSplitView(viewModel: messengerViewModel)
                .tag(PingyRootTab.chats)

            NavigationStack {
                StatusTabView(messengerViewModel: messengerViewModel)
            }
            .tag(PingyRootTab.status)

            NavigationStack {
                CallsTabView(messengerViewModel: messengerViewModel)
            }
            .tag(PingyRootTab.calls)

            NavigationStack {
                SettingsHubView(
                    messengerViewModel: messengerViewModel,
                    themeManager: themeManager
                )
            }
            .tag(PingyRootTab.settings)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomGlassBar
                .padding(.horizontal, PingySpacing.md)
                .padding(.top, 6)
                .padding(.bottom, 4)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var bottomGlassBar: some View {
        HStack(spacing: 8) {
            ForEach(PingyRootTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(PingyTheme.border.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 14, y: 8)
    }

    private func tabButton(for tab: PingyRootTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            guard selectedTab != tab else { return }
            PingyHaptics.softTap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .bold))
                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? PingyTheme.primaryStrong : PingyTheme.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? PingyTheme.primarySoft : Color.clear)
            )
            .overlay {
                if isSelected {
                    Circle()
                        .fill(PingyTheme.primary.opacity(0.2))
                        .frame(width: 34, height: 34)
                        .blur(radius: 10)
                        .offset(y: -2)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(PingyPressableButtonStyle())
    }
}
