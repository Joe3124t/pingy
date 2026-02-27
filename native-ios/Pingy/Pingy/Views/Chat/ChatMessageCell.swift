import SwiftUI

struct ChatMessageCell: View, Equatable {
    let message: Message
    let conversation: Conversation
    let currentUserID: String?
    let isGroupedWithPrevious: Bool
    let decryptedText: String?
    let uploadProgress: Double?
    let canRetryUpload: Bool
    let outgoingState: OutgoingMessageState?
    let canRetryText: Bool
    let onReply: () -> Void
    let onReact: (String) -> Void
    let onRetryUpload: () -> Void
    let onRetryText: () -> Void
    let onOpenImage: ((Message, URL) -> Void)?
    let onLongPress: (() -> Void)?
    let searchHighlightRanges: [NSRange]
    let isStarred: Bool
    let onForward: (() -> Void)?
    let onToggleStar: (() -> Void)?
    let onDeleteForMe: (() -> Void)?
    let reduceGlassEffect: Bool
    let glassOpacityScale: CGFloat
    let glassBlurRadius: CGFloat

    static func == (lhs: ChatMessageCell, rhs: ChatMessageCell) -> Bool {
        lhs.message == rhs.message &&
            lhs.decryptedText == rhs.decryptedText &&
            lhs.uploadProgress == rhs.uploadProgress &&
            lhs.canRetryUpload == rhs.canRetryUpload &&
            lhs.outgoingState == rhs.outgoingState &&
            lhs.canRetryText == rhs.canRetryText &&
            lhs.isGroupedWithPrevious == rhs.isGroupedWithPrevious &&
            lhs.searchHighlightRanges == rhs.searchHighlightRanges &&
            lhs.isStarred == rhs.isStarred &&
            lhs.reduceGlassEffect == rhs.reduceGlassEffect &&
            lhs.glassOpacityScale == rhs.glassOpacityScale &&
            lhs.glassBlurRadius == rhs.glassBlurRadius
    }

    var body: some View {
        MessageBubbleView(
            message: message,
            conversation: conversation,
            currentUserID: currentUserID,
            isGroupedWithPrevious: isGroupedWithPrevious,
            decryptedText: decryptedText,
            uploadProgress: uploadProgress,
            canRetryUpload: canRetryUpload,
            outgoingState: outgoingState,
            canRetryText: canRetryText,
            onReply: onReply,
            onReact: onReact,
            onRetryUpload: onRetryUpload,
            onRetryText: onRetryText,
            onOpenImage: onOpenImage,
            onLongPress: onLongPress,
            searchHighlightRanges: searchHighlightRanges,
            isStarred: isStarred,
            onForward: onForward,
            onToggleStar: onToggleStar,
            onDeleteForMe: onDeleteForMe,
            reduceGlassEffect: reduceGlassEffect,
            glassOpacityScale: glassOpacityScale,
            glassBlurRadius: glassBlurRadius
        )
    }
}
