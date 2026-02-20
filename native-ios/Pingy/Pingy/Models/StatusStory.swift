import Foundation

enum StatusPrivacy: String, Codable, CaseIterable, Identifiable {
    case contacts = "My contacts"
    case custom = "Custom"

    var id: String { rawValue }
}

enum StatusContentType: String, Codable {
    case text
    case image
    case video
}

struct StatusViewer: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let viewedAt: Date
}

struct StatusStory: Codable, Identifiable, Equatable {
    let id: String
    let ownerUserID: String
    let ownerName: String
    let ownerAvatarURL: String?
    let contentType: StatusContentType
    let text: String?
    let mediaURL: String?
    let backgroundHex: String?
    let privacy: StatusPrivacy
    let createdAt: Date
    let expiresAt: Date
    var viewers: [StatusViewer]
}
