import SwiftUI

struct RootView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var themeManager: ThemeManager
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @State private var didBindForCurrentSession = false
    @AppStorage("pingy.v3.language") private var appLanguage = "System"

    var body: some View {
        Group {
            if sessionStore.isAuthenticated {
                PingyTabShellView(
                    messengerViewModel: messengerViewModel,
                    themeManager: themeManager
                )
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
        .environment(\.locale, appLocale)
        .environment(\.layoutDirection, appLayoutDirection)
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

    private var appLocale: Locale {
        switch appLanguage {
        case "Arabic":
            return Locale(identifier: "ar")
        case "English":
            return Locale(identifier: "en")
        default:
            return .autoupdatingCurrent
        }
    }

    private var appLayoutDirection: LayoutDirection {
        switch appLanguage {
        case "Arabic":
            return .rightToLeft
        case "English":
            return .leftToRight
        default:
            let preferredLanguage = Locale.preferredLanguages.first ?? "en"
            let systemCode = Locale(identifier: preferredLanguage).languageCode ?? "en"
            return Locale.characterDirection(forLanguage: systemCode) == .rightToLeft ? .rightToLeft : .leftToRight
        }
    }
}
