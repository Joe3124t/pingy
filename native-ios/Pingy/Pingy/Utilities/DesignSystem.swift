import SwiftUI
import UIKit

enum PingyTheme {
    static let primary = Color(red: 0.04, green: 0.49, blue: 0.55)
    static let primaryStrong = Color(red: 0.02, green: 0.42, blue: 0.48)
    static let primarySoft = Color(red: 0.86, green: 0.95, blue: 0.96)
    static let background = Color(red: 0.96, green: 0.98, blue: 0.99)
    static let surface = Color.white
    static let textPrimary = Color(red: 0.09, green: 0.12, blue: 0.17)
    static let textSecondary = Color(red: 0.35, green: 0.41, blue: 0.48)
    static let border = Color(red: 0.88, green: 0.91, blue: 0.94)
    static let success = Color(red: 0.13, green: 0.64, blue: 0.36)
    static let danger = Color(red: 0.81, green: 0.20, blue: 0.24)
}

enum PingySpacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
}

enum PingyRadius {
    static let card: CGFloat = 20
    static let bubble: CGFloat = 22
    static let input: CGFloat = 18
}

struct PingyCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PingySpacing.md)
            .background(PingyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous)
                    .stroke(PingyTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
    }
}

extension View {
    func pingyCard() -> some View {
        modifier(PingyCardModifier())
    }
}

struct PingyPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

enum PingyHaptics {
    static func softTap() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}
