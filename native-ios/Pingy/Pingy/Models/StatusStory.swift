import Foundation

enum StatusPrivacy: String, Codable, CaseIterable, Identifiable {
    case contacts
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contacts:
            return "My contacts"
        case .custom:
            return "Custom"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch raw {
        case "custom":
            self = .custom
        default:
            self = .contacts
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

struct StatusUpdateEvent: Codable, Equatable {
    let action: String
    let storyId: String?
    let ownerUserID: String
    let createdAt: String?
}
