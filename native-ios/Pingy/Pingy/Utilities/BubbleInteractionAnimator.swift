import SwiftUI

enum BubbleInteractionAnimator {
    static let pressScale: CGFloat = 0.97
    static let liftedOffsetY: CGFloat = -4
    static let restingOffsetY: CGFloat = 0

    static let baseShadow = ShadowProfile(radius: 9, y: 4, opacity: 0.22)
    static let liftedShadow = ShadowProfile(radius: 14, y: 7, opacity: 0.32)

    static let pressAnimation = Animation.easeOut(duration: 0.14)
    static let releaseAnimation = Animation.spring(response: 0.3, dampingFraction: 0.78)
    static let glowPulseAnimation = Animation.easeOut(duration: 0.22)

    static func glowOpacity(isPressed: Bool, isLifted: Bool) -> Double {
        if isLifted { return 0.20 }
        return isPressed ? 0.12 : 0.06
    }
}

struct ShadowProfile {
    let radius: CGFloat
    let y: CGFloat
    let opacity: Double
}
