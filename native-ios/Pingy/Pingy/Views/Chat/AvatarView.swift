import SwiftUI

struct AvatarView: View {
    let url: String?
    let fallback: String

    var body: some View {
        Group {
            if let urlString = url, let parsed = URL(string: urlString) {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackView
                    @unknown default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: 52, height: 52)
        .background(
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.72, blue: 0.90), Color(red: 0.04, green: 0.57, blue: 0.77)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fallbackView: some View {
        Text(String(fallback.prefix(1)).uppercased())
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}
