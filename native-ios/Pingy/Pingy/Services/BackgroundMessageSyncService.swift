import Foundation
import UIKit
import UserNotifications

@MainActor
final class BackgroundMessageSyncService {
    private let authService: AuthService
    private let conversationService: ConversationService
    private let userDefaults = UserDefaults.standard
    private let cacheKey = "pingy.background.lastConversationFingerprint"

    init(authService: AuthService, conversationService: ConversationService) {
        self.authService = authService
        self.conversationService = conversationService
    }

    func configureBackgroundFetch() {
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    }

    func performBackgroundFetch() async -> UIBackgroundFetchResult {
        guard authService.sessionStore.isAuthenticated else { return .noData }

        do {
            let conversations = try await conversationService.listConversations()
            let previous = cachedFingerprintMap()
            var next: [String: String] = [:]
            var hasNewData = false

            for conversation in conversations {
                let fingerprint = fingerprintForConversation(conversation)
                next[conversation.conversationId] = fingerprint

                let previousValue = previous[conversation.conversationId]
                let changed = previousValue != fingerprint
                if changed, conversation.unreadCount > 0 {
                    hasNewData = true
                    await scheduleLocalNotification(for: conversation)
                }
            }

            userDefaults.set(next, forKey: cacheKey)
            return hasNewData ? .newData : .noData
        } catch {
            AppLogger.error("Background fetch failed: \(error.localizedDescription)")
            return .failed
        }
    }

    private func cachedFingerprintMap() -> [String: String] {
        userDefaults.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
    }

    private func fingerprintForConversation(_ conversation: Conversation) -> String {
        let preview = MessageBodyFormatter.previewText(
            from: conversation.lastMessageBody,
            fallback: MessageBodyFormatter.fallbackLabel(
                forTypeRaw: conversation.lastMessageType,
                mediaName: conversation.lastMessageMediaName
            )
        )
        let timestamp = conversation.lastMessageCreatedAt
            ?? conversation.lastMessageAt
            ?? conversation.updatedAt
            ?? ""
        return "\(timestamp)|\(conversation.unreadCount)|\(preview)"
    }

    private func scheduleLocalNotification(for conversation: Conversation) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        else { return }

        let sender = conversation.participantUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let senderName = sender.isEmpty ? String(localized: "New message") : sender
        let preview = MessageBodyFormatter.previewText(
            from: conversation.lastMessageBody,
            fallback: MessageBodyFormatter.fallbackLabel(
                forTypeRaw: conversation.lastMessageType,
                mediaName: conversation.lastMessageMediaName
            )
        )

        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = preview
        content.sound = .default
        content.threadIdentifier = conversation.conversationId
        content.userInfo = ["conversationId": conversation.conversationId]
        content.badge = NSNumber(value: max(conversation.unreadCount, 1))

        let request = UNNotificationRequest(
            identifier: "bg-conversation-\(conversation.conversationId)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            AppLogger.error("Background local notification failed: \(error.localizedDescription)")
        }
    }
}
