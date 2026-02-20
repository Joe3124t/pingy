import SwiftUI

struct AvatarView: View {
    let url: String?
    let fallback: String
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 16

    var body: some View {
        Group {
            if let parsed = MediaURLResolver.resolve(url) {
                CachedRemoteImage(url: parsed) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                        .tint(.white)
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallbackView: some View {
        Text(String(fallback.prefix(1)).uppercased())
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}
