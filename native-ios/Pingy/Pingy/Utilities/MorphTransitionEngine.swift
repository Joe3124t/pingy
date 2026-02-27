import SwiftUI

enum MorphTransitionEngine {
    static let liquidSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let fastEaseOut = Animation.easeOut(duration: 0.2)
    static let messageAppear = Animation.spring(response: 0.28, dampingFraction: 0.86)

    static var liquidMorph: AnyTransition {
        .modifier(
            active: LiquidMorphModifier(scale: 0.95, opacity: 0),
            identity: LiquidMorphModifier(scale: 1, opacity: 1)
        )
    }

    static var messageInsertion: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        )
    }
}

private struct LiquidMorphModifier: ViewModifier {
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
    }
}
