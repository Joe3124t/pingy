import SwiftUI

struct RootView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var sessionStore: SessionStore
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if sessionStore.isAuthenticated {
                MessengerSplitView(viewModel: messengerViewModel)
                    .onAppear {
                        messengerViewModel.bindSocket()
                    }
                    .task(id: sessionStore.currentUser?.id) {
                        await messengerViewModel.reloadAll()
                    }
            } else {
                AuthView(viewModel: authViewModel)
            }
        }
        .preferredColorScheme(resolvedColorScheme)
        .animation(.spring(duration: 0.28), value: sessionStore.isAuthenticated)
    }

    private var resolvedColorScheme: ColorScheme? {
        guard let theme = messengerViewModel.currentUserSettings?.themeMode else {
            return nil
        }
        switch theme {
        case .auto:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
