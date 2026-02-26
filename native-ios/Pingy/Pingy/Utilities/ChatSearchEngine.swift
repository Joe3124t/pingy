import Foundation

struct ChatSearchMatch: Identifiable, Equatable {
    let id: String
    let messageID: String
    let range: NSRange
    let value: String
}

struct ChatSearchResultSet: Equatable {
    let matches: [ChatSearchMatch]
    let rangesByMessageID: [String: [NSRange]]

    static let empty = ChatSearchResultSet(matches: [], rangesByMessageID: [:])
}

enum ChatSearchEngine {
    static func search(
        query: String,
        messages: [Message],
        decryptedBodyByID: [String: String]
    ) -> ChatSearchResultSet {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return .empty }

        var matches: [ChatSearchMatch] = []
        var rangesByMessageID: [String: [NSRange]] = [:]

        for message in messages {
            let searchableText = resolvedMessageText(message, decryptedBodyByID: decryptedBodyByID)
            guard !searchableText.isEmpty else { continue }

            let nsText = searchableText as NSString
            let textLength = nsText.length
            var searchRange = NSRange(location: 0, length: textLength)

            while searchRange.location < textLength {
                let found = nsText.range(
                    of: trimmedQuery,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )

                guard found.location != NSNotFound, found.length > 0 else { break }

                let value = nsText.substring(with: found)
                let matchID = "\(message.id)-\(found.location)-\(found.length)"
                let match = ChatSearchMatch(
                    id: matchID,
                    messageID: message.id,
                    range: found,
                    value: value
                )
                matches.append(match)
                rangesByMessageID[message.id, default: []].append(found)

                let nextLocation = found.location + max(found.length, 1)
                guard nextLocation < textLength else { break }
                searchRange = NSRange(location: nextLocation, length: textLength - nextLocation)
            }
        }

        return ChatSearchResultSet(matches: matches, rangesByMessageID: rangesByMessageID)
    }

    private static func resolvedMessageText(
        _ message: Message,
        decryptedBodyByID: [String: String]
    ) -> String {
        if let decrypted = decryptedBodyByID[message.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !decrypted.isEmpty
        {
            return decrypted
        }

        return MessageBodyFormatter.previewText(
            from: message.body,
            fallback: MessageBodyFormatter.fallbackLabel(for: message.type, mediaName: message.mediaName)
        )
    }
}
