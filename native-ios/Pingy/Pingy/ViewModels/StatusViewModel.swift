import Foundation

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var stories: [StatusStory] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var selectedPrivacy: StatusPrivacy = .contacts {
        didSet {
            defaults.set(selectedPrivacy.rawValue, forKey: statusPrivacyDefaultsKey)
        }
    }

    private let service: StatusService
    private let defaults = UserDefaults.standard
    private let statusPrivacyDefaultsKey = "pingy.v3.statusPrivacy"

    init(service: StatusService) {
        self.service = service
        let storedValue = defaults.string(forKey: statusPrivacyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if storedValue == StatusPrivacy.custom.rawValue || storedValue == "custom" {
            selectedPrivacy = .custom
        } else {
            selectedPrivacy = .contacts
        }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        stories = await service.listActiveStories()
    }

    func postTextStory(
        ownerUserID: String,
        ownerName: String,
        ownerAvatarURL: String?,
        text: String,
        backgroundHex: String
    ) async {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        do {
            try await service.addTextStory(
                ownerUserID: ownerUserID,
                ownerName: ownerName,
                ownerAvatarURL: ownerAvatarURL,
                text: normalized,
                backgroundHex: backgroundHex,
                privacy: selectedPrivacy
            )
            errorMessage = nil
        } catch {
            errorMessage = statusErrorMessage(
                from: error,
                fallback: "Couldn't publish text status right now."
            )
            AppLogger.error("Text status publish failed: \(error.localizedDescription)")
        }
        stories = await service.listActiveStories()
    }

    func postMediaStory(
        ownerUserID: String,
        ownerName: String,
        ownerAvatarURL: String?,
        data: Data,
        fileExtension: String,
        contentType: StatusContentType
    ) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.addMediaStory(
                ownerUserID: ownerUserID,
                ownerName: ownerName,
                ownerAvatarURL: ownerAvatarURL,
                mediaData: data,
                fileExtension: fileExtension,
                contentType: contentType,
                privacy: selectedPrivacy
            )
            stories = await service.listActiveStories()
            errorMessage = nil
        } catch {
            errorMessage = statusErrorMessage(
                from: error,
                fallback: "Couldn't publish status. Please try a different media file."
            )
            AppLogger.error("Media status publish failed: \(error.localizedDescription)")
        }
    }

    func deleteStory(_ storyID: String) async {
        await service.deleteStory(storyID)
        stories = await service.listActiveStories()
    }

    func markViewed(storyID: String, viewerID: String, viewerName: String) async {
        await service.markViewed(storyID: storyID, viewerID: viewerID, viewerName: viewerName)
        stories = await service.listActiveStories()
    }

    private func statusErrorMessage(from error: Error, fallback: String) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .server(_, let message):
                let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    return normalized
                }
            default:
                if let readable = apiError.errorDescription,
                   !readable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    return readable
                }
            }
        }

        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localized.isEmpty {
            return localized
        }

        return fallback
    }
}
