import Foundation

struct User: Codable, Identifiable, Equatable {
    let id: String
    var username: String
    var phoneNumber: String?
    var email: String?
    var avatarUrl: String?
    var bio: String?
    var isOnline: Bool?
    var lastSeen: String?
    var lastLoginAt: String?
    var deviceId: String?
    var showOnlineStatus: Bool?
    var readReceiptsEnabled: Bool?
    var themeMode: ThemeMode?
    var defaultWallpaperUrl: String?
    var totpEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case phoneNumber
        case email
        case avatarUrl
        case bio
        case isOnline
        case lastSeen
        case lastLoginAt
        case deviceId
        case showOnlineStatus
        case readReceiptsEnabled
        case themeMode
        case defaultWallpaperUrl
        case totpEnabled
    }

    var displayName: String {
        username
    }
}
