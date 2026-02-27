import SwiftUI

struct AdaptiveTextStyle {
    let textColor: Color
    let glowColor: Color
    let glowRadius: CGFloat
    let glowYOffset: CGFloat
    let linkTint: Color
}

enum AdaptiveTextEngine {
    static func style(
        for messageType: MessageType,
        isOwnMessage: Bool,
        backgroundLuminance: Double?,
        colorScheme: ColorScheme
    ) -> AdaptiveTextStyle {
        let luminance = backgroundLuminance ?? fallbackLuminance(for: messageType, isOwnMessage: isOwnMessage)
        let isDarkBackground = luminance < 0.42

        if isDarkBackground {
            return AdaptiveTextStyle(
                textColor: Color.white,
                glowColor: Color.white.opacity(0.20),
                glowRadius: 3,
                glowYOffset: 0,
                linkTint: Color.white
            )
        }

        return AdaptiveTextStyle(
            textColor: Color.white.opacity(colorScheme == .dark ? 0.95 : 0.90),
            glowColor: Color.white.opacity(0.10),
            glowRadius: 1.4,
            glowYOffset: 0,
            linkTint: isOwnMessage ? Color.white.opacity(0.92) : PingyTheme.primaryStrong
        )
    }

    static func fallbackLuminance(for messageType: MessageType, isOwnMessage: Bool) -> Double {
        let base: (Double, Double, Double)
        if isOwnMessage {
            base = messageType == .image ? (0.18, 0.37, 0.52) : (0.09, 0.32, 0.48)
        } else {
            base = messageType == .image ? (0.16, 0.19, 0.25) : (0.11, 0.14, 0.21)
        }
        return luminance(red: base.0, green: base.1, blue: base.2)
    }

    private static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linearized(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = linearized(red)
        let g = linearized(green)
        let b = linearized(blue)
        return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    }
}

