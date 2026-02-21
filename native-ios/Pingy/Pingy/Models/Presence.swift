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

struct RecordingEvent: Codable, Equatable {
    let conversationId: String
    let userId: String
    let username: String?
}

enum CallSignalStatus: String, Codable, Equatable {
    case ringing
    case connected
    case declined
    case ended
    case missed
}

struct CallSignalEvent: Codable, Equatable {
    let callId: String
    let conversationId: String
    let fromUserId: String
    let toUserId: String
    let status: CallSignalStatus
    let createdAt: String?
}
