import SwiftUI

struct PingyTabShellView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var themeManager: ThemeManager
    let statusService: StatusService

    @State private var selectedTab: PingyRootTab = .chats
    @State private var chromeCompact = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ContactsTabView(
                viewModel: messengerViewModel,
                onOpenConversation: { conversation in
                    Task {
                        await messengerViewModel.selectConversation(conversation.conversationId)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedTab = .chats
                        }
                    }
                },
                onOpenUser: { user in
                    Task {
                        await messengerViewModel.openOrCreateConversation(with: user)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedTab = .chats
                        }
                    }
                }
            )
            .tag(PingyRootTab.contacts)

            CallsTabView(messengerViewModel: messengerViewModel)
            .tag(PingyRootTab.calls)

            MessengerSplitView(viewModel: messengerViewModel)
                .tag(PingyRootTab.chats)

            StatusTabView(
                messengerViewModel: messengerViewModel,
                statusService: statusService
            )
            .tag(PingyRootTab.status)

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
            VStack(spacing: 7) {
                TopBarView(
                    title: selectedTab.title,
                    subtitle: subtitleForSelectedTab,
                    compact: chromeCompact,
                    isStatusActive: selectedTab == .status,
                    onStatusTap: {
                        selectTab(.status)
                    }
                )

                if messengerViewModel.networkBannerState != .hidden {
                    NetworkStateBannerView(state: messengerViewModel.networkBannerState)
                        .transition(
                            .move(edge: .top)
                                .combined(with: .opacity)
                        )
                }

                if let notice = messengerViewModel.transientNotice {
                    TransientNoticeBannerView(
                        notice: notice,
                        onDismiss: {
                            messengerViewModel.dismissTransientNotice()
                        }
                    )
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowBottomBar {
                FloatingTabBar(
                    selectedTab: $selectedTab,
                    unreadCount: messengerViewModel.totalUnreadCount,
                    compact: chromeCompact,
                    onSelect: { tab in
                        selectTab(tab)
                    }
                )
                    .padding(.horizontal, PingySpacing.md)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    let shouldCompact = value.translation.height < -16
                    if chromeCompact != shouldCompact {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                            chromeCompact = shouldCompact
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        chromeCompact = false
                    }
                }
        )
        .onChange(of: messengerViewModel.activeError) { message in
            guard let message, !message.isEmpty else { return }
            if messengerViewModel.transientNotice?.message != message {
                messengerViewModel.showTransientNotice(message, style: .error, autoDismissAfter: 2.8)
            }
            messengerViewModel.activeError = nil
        }
    }

    private var shouldShowBottomBar: Bool {
        if selectedTab == .chats, messengerViewModel.selectedConversationID != nil {
            return false
        }
        return true
    }

    private var subtitleForSelectedTab: String? {
        switch selectedTab {
        case .contacts:
            return "Find people on Pingy"
        case .calls:
            return "Recent and secure voice calls"
        case .chats:
            if messengerViewModel.totalUnreadCount > 0 {
                return "\(messengerViewModel.totalUnreadCount) unread"
            }
            return "Private conversations"
        case .status:
            return "Stories and updates"
        case .settings:
            return "Account and privacy controls"
        }
    }

    private func selectTab(_ tab: PingyRootTab) {
        guard selectedTab != tab else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedTab = tab
        }
    }
}

private struct TransientNoticeBannerView: View {
    let notice: TransientNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PingyTheme.textPrimary)

            Text(notice.message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PingyTheme.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(PingyTheme.surfaceElevated.opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tintColor.opacity(0.25))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PingyTheme.border.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
    }

    private var iconName: String {
        switch notice.style {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .success:
            return "checkmark.circle.fill"
        }
    }

    private var tintColor: Color {
        switch notice.style {
        case .info:
            return PingyTheme.primary
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        case .success:
            return Color.green
        }
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
