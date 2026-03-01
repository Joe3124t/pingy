import CoreGraphics

struct ReactionLayoutPlacement {
    let reactionCenterX: CGFloat
    let reactionCenterY: CGFloat
    let menuCenterX: CGFloat
    let menuCenterY: CGFloat
}

enum ReactionLayoutFix {
    static func resolve(
        messageFrame: CGRect,
        canvasSize: CGSize,
        reactionSize: CGSize,
        menuSize: CGSize,
        isOwnMessage: Bool
    ) -> ReactionLayoutPlacement {
        let horizontalPadding: CGFloat = 14
        let topSafeInset: CGFloat = 92
        let bottomSafeInset: CGFloat = 94
        let verticalSpacing: CGFloat = 10

        let reactionHalfWidth = reactionSize.width / 2
        let menuHalfWidth = menuSize.width / 2

        // Keep both reaction row and action menu visually centered under the selected message.
        let anchorX = clamp(
            messageFrame.midX,
            min: horizontalPadding + max(reactionHalfWidth, menuHalfWidth),
            max: canvasSize.width - horizontalPadding - max(reactionHalfWidth, menuHalfWidth)
        )

        let availableBottom = canvasSize.height - bottomSafeInset
        let requiredStackHeight = reactionSize.height + verticalSpacing + menuSize.height

        // Preferred placement: directly below the selected bubble.
        var reactionTop = messageFrame.maxY + verticalSpacing
        var menuTop = reactionTop + reactionSize.height + verticalSpacing

        // Fallback to above bubble when there is no enough room below.
        if menuTop + menuSize.height > availableBottom {
            menuTop = messageFrame.minY - verticalSpacing - menuSize.height
            reactionTop = menuTop - verticalSpacing - reactionSize.height
        }

        let maxMenuTop = availableBottom - menuSize.height
        let minReactionTop = topSafeInset
        let maxReactionTop = max(minReactionTop, availableBottom - requiredStackHeight)

        reactionTop = clamp(reactionTop, min: minReactionTop, max: maxReactionTop)
        menuTop = reactionTop + reactionSize.height + verticalSpacing
        if menuTop > maxMenuTop {
            menuTop = maxMenuTop
            reactionTop = max(minReactionTop, menuTop - reactionSize.height - verticalSpacing)
        }
        menuTop = max(topSafeInset, menuTop)

        return ReactionLayoutPlacement(
            reactionCenterX: anchorX,
            reactionCenterY: reactionTop + (reactionSize.height / 2),
            menuCenterX: anchorX,
            menuCenterY: menuTop + (menuSize.height / 2)
        )
    }

    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}
