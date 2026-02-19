import Foundation

struct PresenceSnapshot: Codable, Equatable {
    let onlineUserIds: [String]
}

struct PresenceUpdate: Codable, Equatable {
    let userId: String
    let isOnline: Bool
    let lastSeen: String?
}

struct ProfileUpdateEvent: Codable, Equatable {
    let userId: String
    let username: String
    let avatarUrl: String?
}

struct ConversationWallpaperEvent: Codable, Equatable {
    let conversationId: String
    let wallpaperUrl: String?
    let blurIntensity: Int
}
