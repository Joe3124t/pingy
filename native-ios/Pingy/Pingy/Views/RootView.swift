import SwiftUI

struct RootView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var themeManager: ThemeManager
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @State private var didBindForCurrentSession = false

    var body: some View {
        Group {
            if sessionStore.isAuthenticated {
                MessengerSplitView(viewModel: messengerViewModel)
                    .task(id: sessionStore.currentUser?.id) {
                        if !didBindForCurrentSession {
                            messengerViewModel.bindSocket()
                            didBindForCurrentSession = true
                        }
                        await messengerViewModel.reloadAll()
                    }
            } else {
                AuthView(viewModel: authViewModel)
            }
        }
        .preferredColorScheme(themeManager.preferredColorScheme)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: sessionStore.isAuthenticated)
        .onChange(of: sessionStore.isAuthenticated) { isAuthenticated in
            if isAuthenticated {
                Task {
                    await appEnvironment.pushManager.configure()
                }
                return
            }

            didBindForCurrentSession = false
            messengerViewModel.disconnectSocket()
        }
    }
}
