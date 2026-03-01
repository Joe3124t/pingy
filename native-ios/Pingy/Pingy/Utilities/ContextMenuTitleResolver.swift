import Foundation

enum ContextMenuTitleResolver {
    static func title(
        for message: Message,
        decryptedText: String?,
        fallbackBodyText: String?
    ) -> String {
        switch message.type {
        case .image:
            return String(localized: "Photo")
        case .video:
            return String(localized: "Video")
        case .voice:
            return String(localized: "Voice Message")
        case .file:
            if let mediaName = message.mediaName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !mediaName.isEmpty
            {
                return mediaName
            }
            return String(localized: "File")
        case .text:
            if let decryptedText {
                let trimmed = decryptedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            if let fallbackBodyText {
                let trimmed = fallbackBodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            return String(localized: "Message")
        }
    }
}
