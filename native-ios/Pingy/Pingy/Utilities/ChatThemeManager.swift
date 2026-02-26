import Foundation

@MainActor
final class ChatThemeManager {
    static let shared = ChatThemeManager()

    private init() {}

    @discardableResult
    func applyTheme(
        using viewModel: MessengerViewModel,
        imageData: Data,
        fileName: String,
        mimeType: String,
        blurIntensity: Int,
        announcement: String?
    ) async -> Bool {
        let applied = await viewModel.uploadConversationWallpaper(
            imageData: imageData,
            fileName: fileName,
            mimeType: mimeType,
            blurIntensity: blurIntensity
        )

        guard applied else { return false }

        if let announcement,
           !announcement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            await viewModel.sendText(announcement)
        }

        return true
    }

    @discardableResult
    func resetTheme(
        using viewModel: MessengerViewModel,
        announcement: String?
    ) async -> Bool {
        let reset = await viewModel.resetConversationWallpaper()
        guard reset else { return false }

        if let announcement,
           !announcement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            await viewModel.sendText(announcement)
        }

        return true
    }
}
