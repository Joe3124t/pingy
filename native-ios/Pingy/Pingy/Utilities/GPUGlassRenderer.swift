import SwiftUI

enum GPUGlassRenderer {
    static func material(for blurRadius: CGFloat, colorScheme: ColorScheme) -> Material {
        if blurRadius <= 10 {
            return .ultraThinMaterial
        }
        return colorScheme == .dark ? .thinMaterial : .regularMaterial
    }

    static func borderOpacity(for blurRadius: CGFloat) -> Double {
        blurRadius <= 10 ? 0.08 : 0.12
    }

    static func highlightOpacity(for blurRadius: CGFloat) -> Double {
        blurRadius <= 10 ? 0.14 : 0.22
    }

    static func shouldRasterizeStaticGlass(isFastMotion: Bool) -> Bool {
        !isFastMotion
    }
}

struct GPUGlassContainerModifier: ViewModifier {
    let cornerRadius: CGFloat
    let blurRadius: CGFloat
    let colorScheme: ColorScheme
    let isFastMotion: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GPUGlassRenderer.material(for: blurRadius, colorScheme: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(GPUGlassRenderer.borderOpacity(for: blurRadius)), lineWidth: 0.9)
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(GPUGlassRenderer.highlightOpacity(for: blurRadius)),
                                        Color.clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 20)
                    }
            )
            .compositingGroup()
            .drawingGroup(
                opaque: false,
                colorMode: .linear
            )
            .opacity(isFastMotion ? 0.96 : 1)
    }
}

extension View {
    func gpuGlassContainer(
        cornerRadius: CGFloat,
        blurRadius: CGFloat,
        colorScheme: ColorScheme,
        isFastMotion: Bool
    ) -> some View {
        modifier(
            GPUGlassContainerModifier(
                cornerRadius: cornerRadius,
                blurRadius: blurRadius,
                colorScheme: colorScheme,
                isFastMotion: isFastMotion
            )
        )
    }
}
