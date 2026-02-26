import SwiftUI

struct AvatarView: View {
    let url: String?
    let fallback: String
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 16
    private var usesCircleMask: Bool { cornerRadius >= (size / 2) - 0.5 }

    var body: some View {
        Group {
            if let parsed = MediaURLResolver.resolve(url) {
                CachedRemoteImage(url: parsed) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    fallbackView
                } failure: {
                    fallbackView
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .background(
            LinearGradient(
                colors: [PingyTheme.primary, PingyTheme.primaryStrong],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .mask {
            if usesCircleMask {
                Circle()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            }
        }
    }

    private var fallbackView: some View {
        Text(String(fallback.prefix(1)).uppercased())
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}
