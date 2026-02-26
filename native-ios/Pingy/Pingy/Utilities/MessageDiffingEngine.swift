import Foundation

enum MessageDiffingEngine {
    static func merge(existing: [Message], incoming: [Message]) -> [Message] {
        guard !incoming.isEmpty else {
            return sortChronologically(existing)
        }

        var byID: [String: Message] = [:]
        var idByClientID: [String: String] = [:]

        for message in existing {
            byID[message.id] = message
            if let clientID = normalizedClientID(message.clientId) {
                idByClientID[clientID] = message.id
            }
        }

        for message in incoming {
            if let clientID = normalizedClientID(message.clientId),
               let previousID = idByClientID[clientID],
               previousID != message.id
            {
                byID.removeValue(forKey: previousID)
            }

            if let current = byID[message.id] {
                byID[message.id] = preferredMessage(existing: current, incoming: message)
            } else {
                byID[message.id] = message
            }

            if let clientID = normalizedClientID(message.clientId) {
                idByClientID[clientID] = message.id
            }
        }

        return sortChronologically(Array(byID.values))
    }

    private static func normalizedClientID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func preferredMessage(existing: Message, incoming: Message) -> Message {
        // Prefer message containing richer lifecycle metadata.
        let existingScore = lifecycleScore(for: existing)
        let incomingScore = lifecycleScore(for: incoming)

        if incomingScore != existingScore {
            return incomingScore > existingScore ? incoming : existing
        }

        // If lifecycle score is equal, prefer the most recently created payload.
        let existingDate = parseDate(existing.createdAt)
        let incomingDate = parseDate(incoming.createdAt)
        if existingDate != incomingDate {
            return (incomingDate ?? .distantPast) >= (existingDate ?? .distantPast) ? incoming : existing
        }

        // Fall back to incoming to reflect the freshest backend payload.
        return incoming
    }

    private static func lifecycleScore(for message: Message) -> Int {
        if message.seenAt != nil {
            return 4
        }
        if message.deliveredAt != nil {
            return 3
        }
        if message.id.hasPrefix("local-") {
            return 1
        }
        return 2
    }

    private static func sortChronologically(_ messages: [Message]) -> [Message] {
        messages.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = isoFormatterWithFractional.date(from: value) {
            return date
        }
        if let date = isoFormatter.date(from: value) {
            return date
        }
        return nil
    }

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
