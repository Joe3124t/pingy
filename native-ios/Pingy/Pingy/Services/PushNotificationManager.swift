import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceTokenHex: String?

    private let settingsService: SettingsService

    init(settingsService: SettingsService) {
        self.settingsService = settingsService
        super.init()
    }

    func configure() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorizationStatus = granted ? .authorized : .denied
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            AppLogger.error("Push permission request failed: \(error.localizedDescription)")
        }
    }

    func didRegisterDeviceToken(_ token: Data) {
        let tokenHex = token.map { String(format: "%02.2hhx", $0) }.joined()
        deviceTokenHex = tokenHex

        Task {
            await settingsService.registerAPNsToken(tokenHex)
        }
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        guard let conversationID = userInfo["conversationId"] as? String else { return }
        NotificationCenter.default.post(
            name: .pingyOpenConversationFromPush,
            object: nil,
            userInfo: ["conversationId": conversationID]
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleRemoteNotification(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
}
