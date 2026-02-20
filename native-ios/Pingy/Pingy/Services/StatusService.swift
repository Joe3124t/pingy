import Foundation

actor StatusService {
    static let shared = StatusService()

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let storeKey = "pingy.v3.status.stories"

    private lazy var mediaDirectoryURL: URL = {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("status-media", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func listActiveStories() -> [StatusStory] {
        var stories = loadStories()
        let now = Date()
        let expired = stories.filter { $0.expiresAt <= now }
        stories.removeAll { $0.expiresAt <= now }
        if !expired.isEmpty {
            expired.forEach { cleanupMedia(for: $0) }
            saveStories(stories)
        }

        return stories.sorted { $0.createdAt > $1.createdAt }
    }

    func addTextStory(
        ownerUserID: String,
        ownerName: String,
        ownerAvatarURL: String?,
        text: String,
        backgroundHex: String,
        privacy: StatusPrivacy
    ) {
        var stories = loadStories()
        stories.insert(
            StatusStory(
                id: UUID().uuidString,
                ownerUserID: ownerUserID,
                ownerName: ownerName,
                ownerAvatarURL: ownerAvatarURL,
                contentType: .text,
                text: text,
                mediaURL: nil,
                backgroundHex: backgroundHex,
                privacy: privacy,
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(24 * 60 * 60),
                viewers: []
            ),
            at: 0
        )
        saveStories(stories)
    }

    func addMediaStory(
        ownerUserID: String,
        ownerName: String,
        ownerAvatarURL: String?,
        mediaData: Data,
        fileExtension: String,
        contentType: StatusContentType,
        privacy: StatusPrivacy
    ) throws {
        let mediaURL = try persistMedia(data: mediaData, fileExtension: fileExtension)
        var stories = loadStories()
        stories.insert(
            StatusStory(
                id: UUID().uuidString,
                ownerUserID: ownerUserID,
                ownerName: ownerName,
                ownerAvatarURL: ownerAvatarURL,
                contentType: contentType,
                text: nil,
                mediaURL: mediaURL.absoluteString,
                backgroundHex: nil,
                privacy: privacy,
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(24 * 60 * 60),
                viewers: []
            ),
            at: 0
        )
        saveStories(stories)
    }

    func markViewed(storyID: String, viewerID: String, viewerName: String) {
        var stories = loadStories()
        guard let index = stories.firstIndex(where: { $0.id == storyID }) else { return }
        if stories[index].viewers.contains(where: { $0.id == viewerID }) {
            return
        }

        stories[index].viewers.append(
            StatusViewer(
                id: viewerID,
                name: viewerName,
                viewedAt: Date()
            )
        )
        saveStories(stories)
    }

    func deleteStory(_ storyID: String) {
        var stories = loadStories()
        guard let index = stories.firstIndex(where: { $0.id == storyID }) else { return }
        let removed = stories.remove(at: index)
        cleanupMedia(for: removed)
        saveStories(stories)
    }

    private func persistMedia(data: Data, fileExtension: String) throws -> URL {
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedExt = ext.isEmpty ? "bin" : ext
        let fileURL = mediaDirectoryURL.appendingPathComponent("\(UUID().uuidString).\(normalizedExt)")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func cleanupMedia(for story: StatusStory) {
        guard let raw = story.mediaURL, let url = URL(string: raw), url.isFileURL else { return }
        try? fileManager.removeItem(at: url)
    }

    private func loadStories() -> [StatusStory] {
        guard let data = defaults.data(forKey: storeKey) else { return [] }
        return (try? decoder.decode([StatusStory].self, from: data)) ?? []
    }

    private func saveStories(_ stories: [StatusStory]) {
        guard let data = try? encoder.encode(stories) else { return }
        defaults.set(data, forKey: storeKey)
    }
}
