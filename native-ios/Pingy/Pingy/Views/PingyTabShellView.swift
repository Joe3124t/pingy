import SwiftUI

struct PingyTabShellView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var callSignalingService: CallSignalingService
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
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowBottomBar {
                FloatingGlassTabBar(
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
        .fullScreenCover(
            item: Binding(
                get: { callSignalingService.activeSession },
                set: { value in
                    if value == nil {
                        callSignalingService.dismissCallUI()
                    }
                }
            )
        ) { session in
            CallView(
                session: session,
                onAccept: {
                    messengerViewModel.acceptActiveCall()
                },
                onDecline: {
                    messengerViewModel.declineActiveCall()
                },
                onToggleMute: {
                    messengerViewModel.toggleCallMute()
                },
                onToggleSpeaker: {
                    messengerViewModel.toggleCallSpeaker()
                },
                onEnd: {
                    messengerViewModel.endActiveCall()
                }
            )
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
