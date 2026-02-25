import SwiftUI

@main
struct PingyApp: App {
    @StateObject private var environment = AppEnvironment()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let memoryCapacity = 60 * 1024 * 1024
        let diskCapacity = 300 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: "PingyURLCache")
    }

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
                appDelegate.backgroundSyncService = environment.backgroundMessageSyncService
                environment.backgroundMessageSyncService.configureBackgroundFetch()
                await environment.bootstrap()
            }
        }
    }
}
