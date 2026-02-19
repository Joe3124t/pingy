import Foundation

enum MessageType: String, Codable, CaseIterable {
    case text
    case image
    case video
    case file
    case voice
}

struct MessageReply: Codable, Equatable {
    let id: String
    let senderId: String
    let senderUsername: String?
    let type: MessageType?
    let body: JSONValue?
    let isEncrypted: Bool?
    let mediaName: String?
    let createdAt: String?
}

struct MessageReaction: Codable, Equatable {
    let emoji: String
    let count: Int
    let reactedByMe: Bool
}

struct Message: Codable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let senderId: String
    let senderUsername: String?
    let senderAvatarUrl: String?
    let recipientId: String
    let replyToMessageId: String?
    let type: MessageType
    let body: JSONValue?
    let isEncrypted: Bool
    let mediaUrl: String?
    let mediaName: String?
    let mediaMime: String?
    let mediaSize: Int?
    let voiceDurationMs: Int?
    let clientId: String?
    let createdAt: String
    var deliveredAt: String?
    var seenAt: String?
    let replyTo: MessageReply?
    var reactions: [MessageReaction]

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case senderId
        case senderUsername
        case senderAvatarUrl
        case recipientId
        case replyToMessageId
        case type
        case body
        case isEncrypted
        case mediaUrl
        case mediaName
        case mediaMime
        case mediaSize
        case voiceDurationMs
        case clientId
        case createdAt
        case deliveredAt
        case seenAt
        case replyTo
        case reactions
    }
}

struct MessageListResponse: Codable {
    let messages: [Message]
}

struct MessageResponse: Codable {
    let message: Message
}

struct MessageLifecycleUpdate: Codable, Equatable {
    let id: String
    let conversationId: String
    let senderId: String
    let deliveredAt: String?
    let seenAt: String?
}

struct SeenUpdatesResponse: Codable {
    let updates: [MessageLifecycleUpdate]
}

struct TypingEvent: Codable, Equatable {
    let conversationId: String
    let userId: String
    let username: String?
}

struct ReactionUpdate: Codable, Equatable {
    let messageId: String
    let conversationId: String
    let reactions: [MessageReaction]
    let action: String?
    let emoji: String?
}

struct ReactionUpdateResponse: Codable {
    let update: ReactionUpdate
}
