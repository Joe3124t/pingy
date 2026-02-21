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
    let statusService: StatusService

    @State private var selectedTab: PingyRootTab = .chats

    var body: some View {
        TabView(selection: $selectedTab) {
            MessengerSplitView(viewModel: messengerViewModel)
                .tag(PingyRootTab.chats)

            NavigationStack {
                StatusTabView(
                    messengerViewModel: messengerViewModel,
                    statusService: statusService
                )
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if messengerViewModel.networkBannerState != .hidden {
                NetworkStateBannerView(state: messengerViewModel.networkBannerState)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                    )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowBottomBar {
                bottomGlassBar
                    .padding(.horizontal, PingySpacing.md)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var shouldShowBottomBar: Bool {
        !(selectedTab == .chats && messengerViewModel.isCompactChatDetailPresented)
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
                Text(LocalizedStringKey(tab.title))
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

private struct NetworkStateBannerView: View {
    let state: NetworkBannerState

    var body: some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .tint(PingyTheme.textPrimary)
                    .controlSize(.small)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PingyTheme.textPrimary)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundTint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PingyTheme.border.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
    }

    private var title: String {
        switch state {
        case .connecting:
            return "Connecting..."
        case .waitingForInternet:
            return "Waiting for internet..."
        case .updating:
            return "Updating..."
        case .hidden:
            return ""
        }
    }

    private var iconName: String {
        switch state {
        case .waitingForInternet:
            return "wifi.slash"
        case .connecting:
            return "bolt.horizontal.circle"
        case .updating:
            return "arrow.triangle.2.circlepath"
        case .hidden:
            return ""
        }
    }

    private var showsProgress: Bool {
        state == .connecting || state == .updating
    }

    private var backgroundTint: Color {
        switch state {
        case .waitingForInternet:
            return Color.orange.opacity(0.16)
        case .connecting:
            return Color.yellow.opacity(0.12)
        case .updating:
            return PingyTheme.primarySoft.opacity(0.34)
        case .hidden:
            return .clear
        }
    }
}
