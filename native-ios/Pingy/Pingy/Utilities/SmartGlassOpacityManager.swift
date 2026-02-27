import SwiftUI

enum SmartGlassOpacityManager {
    static func bubbleOpacity(for messageType: MessageType) -> Double {
        switch messageType {
        case .image, .video:
            return 0.45
        default:
            return 0.65
        }
    }

    static func adjustedBubbleOpacity(for messageType: MessageType, isFastScrolling: Bool) -> Double {
        let base = bubbleOpacity(for: messageType)
        guard isFastScrolling else { return base }
        return max(0.30, base - 0.14)
    }

    static func glossyHighlightOpacity(for messageType: MessageType, isFastScrolling: Bool) -> Double {
        guard !isFastScrolling else { return 0 }
        switch messageType {
        case .image, .video:
            return 0
        default:
            return 0.06
        }
    }

    static func bubbleFillStyle(isFastScrolling: Bool) -> AnyShapeStyle {
        if isFastScrolling {
            return AnyShapeStyle(Color.black.opacity(0.20))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    static func estimatedLuminance(
        for messageType: MessageType,
        isOwnMessage: Bool,
        colorScheme: ColorScheme
    ) -> Double {
        let opacity = adjustedBubbleOpacity(for: messageType, isFastScrolling: false)
        let color: UIColor

        if isOwnMessage {
            color = UIColor(red: 0.07, green: 0.34, blue: 0.50, alpha: opacity)
        } else {
            color = UIColor(red: 0.11, green: 0.14, blue: 0.22, alpha: opacity)
        }

        return color.luminanceValue
    }
}

private extension UIColor {
    var luminanceValue: Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return 0.2
        }

        func linearized(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        let r = linearized(Double(red))
        let g = linearized(Double(green))
        let b = linearized(Double(blue))
        return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    }
}
