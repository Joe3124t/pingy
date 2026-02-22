import SwiftUI

struct PingyTabShellView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var callSignalingService: CallSignalingService
    let statusService: StatusService

    @State private var selectedTab: PingyRootTab = .chats

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowBottomBar {
                FloatingGlassTabBar(
                    selectedTab: $selectedTab,
                    unreadCount: messengerViewModel.totalUnreadCount,
                    compact: false,
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

    private func selectTab(_ tab: PingyRootTab) {
        guard selectedTab != tab else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedTab = tab
        }
    }
}
