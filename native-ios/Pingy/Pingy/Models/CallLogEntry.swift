import Foundation

enum CallDirection: String, Codable {
    case incoming
    case outgoing
    case missed
}

enum CallType: String, Codable {
    case voice
}

struct CallLogEntry: Codable, Identifiable, Equatable {
    let id: String
    let conversationID: String
    let participantID: String
    let participantName: String
    let participantAvatarURL: String?
    let direction: CallDirection
    let type: CallType
    let createdAt: Date
    let durationSeconds: Int
}
