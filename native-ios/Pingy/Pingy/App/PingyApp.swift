import SwiftUI

@main
struct PingyApp: App {
    @StateObject private var environment = AppEnvironment()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(
                authViewModel: environment.authViewModel,
                messengerViewModel: environment.messengerViewModel,
                sessionStore: environment.sessionStore,
                themeManager: environment.themeManager
            )
            .environmentObject(environment)
            .environmentObject(environment.themeManager)
            .task {
                appDelegate.pushManager = environment.pushManager
                await environment.bootstrap()
            }
        }
    }
}
