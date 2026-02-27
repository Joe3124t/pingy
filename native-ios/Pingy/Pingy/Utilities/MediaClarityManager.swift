import SwiftUI

struct FullscreenMediaEnhancement {
    let brightnessBoost: Double
    let contrastBoost: Double
    let dimOpacity: Double
    let fadeDuration: Double
}

enum MediaClarityManager {
    static let fullscreenEnhancement = FullscreenMediaEnhancement(
        brightnessBoost: 0.05,
        contrastBoost: 1.04,
        dimOpacity: 0.42,
        fadeDuration: 0.2
    )

    static func mediaBackdrop(
        isOwnMessage: Bool,
        colorScheme: ColorScheme,
        opacity: Double
    ) -> some ShapeStyle {
        let start = isOwnMessage
            ? Color(red: 0.09, green: 0.38, blue: 0.54).opacity(opacity)
            : Color(red: 0.14, green: 0.17, blue: 0.25).opacity(opacity)
        let end = isOwnMessage
            ? Color(red: 0.05, green: 0.24, blue: 0.36).opacity(opacity)
            : Color(red: 0.08, green: 0.10, blue: 0.16).opacity(opacity)

        return LinearGradient(
            colors: [start, end],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
