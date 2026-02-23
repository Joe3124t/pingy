import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceTokenHex: String?

    private let settingsService: SettingsService
    private let userDefaults = UserDefaults.standard
    private let tokenDefaultsKey = "pingy.apns.deviceTokenHex"

    init(settingsService: SettingsService) {
        self.settingsService = settingsService
        super.init()
        deviceTokenHex = userDefaults.string(forKey: tokenDefaultsKey)
    }

    func configure() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        authorizationStatus = await center.notificationSettings().authorizationStatus

        if authorizationStatus == .notDetermined {
            await requestPermission()
            authorizationStatus = await center.notificationSettings().authorizationStatus
        }

        if authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral {
            await syncStoredTokenIfNeeded()
            UIApplication.shared.registerForRemoteNotifications()
        }
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
        userDefaults.set(tokenHex, forKey: tokenDefaultsKey)

        Task {
            await settingsService.registerAPNsToken(tokenHex)
        }
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        if let badge = extractBadge(from: userInfo) {
            UIApplication.shared.applicationIconBadgeNumber = badge
        }

        guard let conversationID = extractConversationId(from: userInfo) else { return }
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
        if let badge = extractBadge(from: notification.request.content.userInfo) {
            UIApplication.shared.applicationIconBadgeNumber = badge
        }
        if UIApplication.shared.applicationState == .active {
            completionHandler([.badge])
        } else {
            completionHandler([.banner, .list, .sound, .badge])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleRemoteNotification(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }

    private func extractConversationId(from userInfo: [AnyHashable: Any]) -> String? {
        if let direct = userInfo["conversationId"] as? String, !direct.isEmpty {
            return direct
        }

        if let idValue = userInfo["conversationId"] {
            let stringValue = String(describing: idValue).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stringValue.isEmpty, stringValue != "<null>" {
                return stringValue
            }
        }

        if let aps = userInfo["aps"] as? [String: Any],
           let threadID = aps["thread-id"] as? String,
           !threadID.isEmpty
        {
            return threadID
        }

        return nil
    }

    private func extractBadge(from userInfo: [AnyHashable: Any]) -> Int? {
        if let aps = userInfo["aps"] as? [String: Any] {
            if let badgeInt = aps["badge"] as? Int {
                return badgeInt
            }
            if let badgeString = aps["badge"] as? String, let parsed = Int(badgeString) {
                return parsed
            }
        }
        return nil
    }

    private func syncStoredTokenIfNeeded() async {
        guard let token = deviceTokenHex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return }

        await settingsService.registerAPNsToken(token)
    }
}
