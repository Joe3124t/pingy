import Foundation

struct Conversation: Codable, Identifiable, Equatable {
    let conversationId: String
    let type: String
    let createdAt: String?
    let updatedAt: String?
    let lastMessageAt: String?
    let participantId: String
    var participantUsername: String
    var participantAvatarUrl: String?
    var participantIsOnline: Bool
    var participantLastSeen: String?
    var isBlocked: Bool
    var blockedByMe: Bool
    var blockedByParticipant: Bool
    var participantPublicKeyJwk: PublicKeyJWK?
    var lastMessageId: String?
    var lastMessageType: String?
    var lastMessageBody: JSONValue?
    var lastMessageIsEncrypted: Bool?
    var lastMessageMediaName: String?
    var lastMessageCreatedAt: String?
    var lastMessageSenderId: String?
    var unreadCount: Int
    var wallpaperUrl: String?
    var blurIntensity: Int

    var id: String { conversationId }

    enum CodingKeys: String, CodingKey {
        case conversationId
        case type
        case createdAt
        case updatedAt
        case lastMessageAt
        case participantId
        case participantUsername
        case participantAvatarUrl
        case participantIsOnline
        case participantLastSeen
        case isBlocked
        case blockedByMe
        case blockedByParticipant
        case participantPublicKeyJwk
        case lastMessageId
        case lastMessageType
        case lastMessageBody
        case lastMessageIsEncrypted
        case lastMessageMediaName
        case lastMessageCreatedAt
        case lastMessageSenderId
        case unreadCount
        case wallpaperUrl
        case blurIntensity
    }
}

struct ConversationListResponse: Codable {
    let conversations: [Conversation]
}

struct ConversationResponse: Codable {
    let conversation: Conversation
}
