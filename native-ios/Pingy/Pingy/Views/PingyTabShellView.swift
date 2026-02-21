import SwiftUI

private enum PingyRootTab: String, CaseIterable, Identifiable {
    case contacts
    case calls
    case chats
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contacts:
            return "Contacts"
        case .calls:
            return "Calls"
        case .chats:
            return "Chats"
        case .settings:
            return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .contacts:
            return "person.2.fill"
        case .calls:
            return "phone.fill"
        case .chats:
            return "bubble.left.and.bubble.right.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

struct PingyTabShellView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var themeManager: ThemeManager

    @State private var selectedTab: PingyRootTab = .chats
    @State private var barDragOffset: CGFloat = 0

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

            NavigationStack {
                CallsTabView(messengerViewModel: messengerViewModel)
            }
            .tag(PingyRootTab.calls)

            MessengerSplitView(viewModel: messengerViewModel)
                .tag(PingyRootTab.chats)

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
            VStack(spacing: 6) {
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
                HStack(alignment: .bottom, spacing: 10) {
                    bottomGlassBar
                    floatingSearchOrb
                }
                    .padding(.horizontal, PingySpacing.md)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
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

    private var bottomGlassBar: some View {
        HStack(spacing: 8) {
            ForEach(PingyRootTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.9)
                .blur(radius: 0.2)
                .padding(0.5)
        }
        .overlay(alignment: .leading) {
            LinearGradient(
                colors: [Color.white.opacity(0.28), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .blendMode(.screen)
            .opacity(0.6)
            .offset(x: barDragOffset * 0.35)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(PingyTheme.border.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 18, y: 10)
        .rotation3DEffect(.degrees(Double(barDragOffset / 12)), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(tabBarScale)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    barDragOffset = max(-36, min(36, value.translation.width))
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        barDragOffset = 0
                    }
                }
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: tabBarScale)
    }

    private func tabButton(for tab: PingyRootTab) -> some View {
        let isSelected = selectedTab == tab
        let isPrimary = tab == .chats

        return Button {
            guard selectedTab != tab else { return }
            PingyHaptics.softTap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: isPrimary ? 17 : 15, weight: .bold))
                Text(LocalizedStringKey(tab.title))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isPrimary ? 9 : 8)
            .foregroundStyle(isSelected ? PingyTheme.primaryStrong : PingyTheme.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? PingyTheme.primarySoft.opacity(isPrimary ? 0.95 : 0.78) : Color.clear)
            )
            .overlay {
                if isSelected {
                    Circle()
                        .fill(PingyTheme.primary.opacity(isPrimary ? 0.35 : 0.2))
                        .frame(width: isPrimary ? 40 : 34, height: isPrimary ? 40 : 34)
                        .blur(radius: isPrimary ? 12 : 10)
                        .offset(y: -2)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if tab == .chats, messengerViewModel.totalUnreadCount > 0 {
                    Text("\(min(99, messengerViewModel.totalUnreadCount))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: -8, y: 3)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: messengerViewModel.totalUnreadCount)
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isSelected)
        }
        .buttonStyle(PingyPressableButtonStyle())
    }

    private var floatingSearchOrb: some View {
        Button {
            PingyHaptics.softTap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = .contacts
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PingyTheme.textPrimary)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 0.9)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 10, y: 6)
        }
        .buttonStyle(PingyPressableButtonStyle())
    }

    private var tabBarScale: CGFloat {
        if selectedTab == .chats && messengerViewModel.isCompactChatDetailPresented {
            return 0.94
        }
        return 1
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
