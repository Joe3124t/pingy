import Foundation

@MainActor
final class StatusViewModel: ObservableObject {
    @Published var stories: [StatusStory] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var selectedPrivacy: StatusPrivacy = .contacts

    private let service: StatusService

    init(service: StatusService = .shared) {
        self.service = service
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
        await service.addTextStory(
            ownerUserID: ownerUserID,
            ownerName: ownerName,
            ownerAvatarURL: ownerAvatarURL,
            text: normalized,
            backgroundHex: backgroundHex,
            privacy: selectedPrivacy
        )
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
            errorMessage = "Couldn't publish status. Please try a different media file."
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
}
