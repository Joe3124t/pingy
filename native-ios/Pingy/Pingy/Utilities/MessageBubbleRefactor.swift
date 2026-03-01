import SwiftUI

enum MessageBubbleRefactor {
    static func contentTextColor(isOwnMessage: Bool) -> Color {
        isOwnMessage ? Color.white : Color.white.opacity(0.98)
    }

    static func timestampColor(isOwnMessage: Bool) -> Color {
        isOwnMessage ? Color.white.opacity(0.96) : Color.white.opacity(0.94)
    }

    static func metadataTextColor(isOwnMessage: Bool) -> Color {
        isOwnMessage ? Color.white.opacity(0.98) : Color.white.opacity(0.96)
    }
}
