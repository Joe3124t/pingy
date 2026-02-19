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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        senderId = try container.decode(String.self, forKey: .senderId)
        senderUsername = try container.decodeIfPresent(String.self, forKey: .senderUsername)
        senderAvatarUrl = try container.decodeIfPresent(String.self, forKey: .senderAvatarUrl)
        recipientId = try container.decode(String.self, forKey: .recipientId)
        replyToMessageId = try container.decodeIfPresent(String.self, forKey: .replyToMessageId)

        if let decodedType = try? container.decode(MessageType.self, forKey: .type) {
            type = decodedType
        } else {
            let rawType = try container.decode(String.self, forKey: .type)
            type = MessageType(rawValue: rawType) ?? .text
        }

        body = try container.decodeIfPresent(JSONValue.self, forKey: .body)
        isEncrypted = try container.decode(Bool.self, forKey: .isEncrypted)
        mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
        mediaName = try container.decodeIfPresent(String.self, forKey: .mediaName)
        mediaMime = try container.decodeIfPresent(String.self, forKey: .mediaMime)
        mediaSize = container.decodeLossyIntIfPresent(forKey: .mediaSize)
        voiceDurationMs = container.decodeLossyIntIfPresent(forKey: .voiceDurationMs)
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        deliveredAt = try container.decodeIfPresent(String.self, forKey: .deliveredAt)
        seenAt = try container.decodeIfPresent(String.self, forKey: .seenAt)
        replyTo = try container.decodeIfPresent(MessageReply.self, forKey: .replyTo)
        reactions = try container.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
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
