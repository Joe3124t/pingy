import Foundation

struct User: Codable, Identifiable, Equatable {
    let id: String
    var username: String
    var email: String?
    var avatarUrl: String?
    var bio: String?
    var isOnline: Bool?
    var lastSeen: String?
    var showOnlineStatus: Bool?
    var readReceiptsEnabled: Bool?
    var themeMode: ThemeMode?
    var defaultWallpaperUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case avatarUrl
        case bio
        case isOnline
        case lastSeen
        case showOnlineStatus
        case readReceiptsEnabled
        case themeMode
        case defaultWallpaperUrl
    }
}
