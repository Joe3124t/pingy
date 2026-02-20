import SwiftUI
import UIKit

enum PingyTheme {
    static let primary = Color("AccentColor")
    static let primaryStrong = Color("AccentColorStrong")
    static let primarySoft = Color("AccentColorSoft")

    static let background = Color(uiColor: UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.black
        }
        return UIColor.systemGroupedBackground
    })

    static let surface = Color(uiColor: UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1.0)
        }
        return UIColor.secondarySystemGroupedBackground
    })

    static let surfaceElevated = Color(uiColor: UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0)
        }
        return UIColor.tertiarySystemGroupedBackground
    })

    static let inputBackground = Color(uiColor: UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0)
        }
        return UIColor.systemBackground
    })

    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let border = Color(uiColor: .separator)

    static let success = Color(uiColor: .systemGreen)
    static let danger = Color(uiColor: .systemRed)
    static let warning = Color(uiColor: .systemOrange)

    static let sentBubbleStart = Color("AccentColor")
    static let sentBubbleEnd = Color("AccentColorStrong")

    static let receivedBubble = Color(uiColor: UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0)
        }
        return UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
    })

    static let reactionChipBackground = Color(uiColor: UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.20, green: 0.22, blue: 0.25, alpha: 1.0)
        }
        return UIColor.white
    })

    static func wallpaperFallback(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(uiColor: .black),
                    Color(uiColor: UIColor(red: 0.03, green: 0.08, blue: 0.12, alpha: 1.0)),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(uiColor: UIColor(red: 0.95, green: 0.98, blue: 1.0, alpha: 1.0)),
                Color(uiColor: UIColor(red: 0.90, green: 0.96, blue: 0.98, alpha: 1.0)),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func wallpaperOverlay(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.27) : Color.white.opacity(0.14)
    }

    static func shadowColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.08)
    }
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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(PingySpacing.md)
            .background(PingyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous)
                    .stroke(PingyTheme.border.opacity(colorScheme == .dark ? 0.45 : 0.3), lineWidth: 1)
            )
            .shadow(
                color: PingyTheme.shadowColor(for: colorScheme),
                radius: colorScheme == .dark ? 7 : 12,
                y: colorScheme == .dark ? 2 : 6
            )
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
