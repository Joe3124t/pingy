import Foundation

struct LocalConversationWallpaper: Codable, Equatable {
    let conversationId: String
    let wallpaperUrl: String
    let blurIntensity: Int
    let updatedAt: Date
}

actor ConversationWallpaperStore {
    static let shared = ConversationWallpaperStore()

    private let defaults = UserDefaults.standard
    private let defaultsKey = "pingy.local.chat.wallpapers.v1"
    private let fileManager = FileManager.default
    private var records: [String: LocalConversationWallpaper] = [:]

    init() {
        records = loadRecords()
    }

    func applyOverrides(to conversations: [Conversation]) -> [Conversation] {
        conversations.map { conversation in
            guard let record = records[conversation.conversationId] else {
                return conversation
            }

            var updated = conversation
            updated.wallpaperUrl = record.wallpaperUrl
            updated.blurIntensity = record.blurIntensity
            return updated
        }
    }

    func saveImage(
        conversationId: String,
        imageData: Data,
        fileName: String,
        blurIntensity: Int
    ) throws -> ConversationWallpaperEvent {
        let ext = normalizedExtension(from: fileName)
        let directory = try wallpapersDirectory()
        let fileURL = directory.appendingPathComponent("\(conversationId).\(ext)", isDirectory: false)

        try imageData.write(to: fileURL, options: [.atomic])

        let record = LocalConversationWallpaper(
            conversationId: conversationId,
            wallpaperUrl: fileURL.absoluteString,
            blurIntensity: max(0, min(20, blurIntensity)),
            updatedAt: Date()
        )

        records[conversationId] = record
        persistRecords()

        return ConversationWallpaperEvent(
            conversationId: conversationId,
            wallpaperUrl: record.wallpaperUrl,
            blurIntensity: record.blurIntensity
        )
    }

    func saveRemoteURL(
        conversationId: String,
        wallpaperURL: String,
        blurIntensity: Int
    ) -> ConversationWallpaperEvent {
        let record = LocalConversationWallpaper(
            conversationId: conversationId,
            wallpaperUrl: wallpaperURL,
            blurIntensity: max(0, min(20, blurIntensity)),
            updatedAt: Date()
        )
        records[conversationId] = record
        persistRecords()

        return ConversationWallpaperEvent(
            conversationId: conversationId,
            wallpaperUrl: record.wallpaperUrl,
            blurIntensity: record.blurIntensity
        )
    }

    func reset(conversationId: String) throws {
        guard let existing = records.removeValue(forKey: conversationId) else {
            return
        }

        if let url = URL(string: existing.wallpaperUrl), url.isFileURL, fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }

        persistRecords()
    }

    private func normalizedExtension(from fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = ext.lowercased()

        if normalized.isEmpty {
            return "jpg"
        }

        return normalized
    }

    private func wallpapersDirectory() throws -> URL {
        let baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let wallpapersDir = baseDir.appendingPathComponent("PingyConversationWallpapers", isDirectory: true)

        if !fileManager.fileExists(atPath: wallpapersDir.path) {
            try fileManager.createDirectory(at: wallpapersDir, withIntermediateDirectories: true)
        }

        return wallpapersDir
    }

    private func loadRecords() -> [String: LocalConversationWallpaper] {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: LocalConversationWallpaper].self, from: data)
        } catch {
            AppLogger.error("Failed to decode local wallpaper store: \(error.localizedDescription)")
            return [:]
        }
    }

    private func persistRecords() {
        do {
            let data = try JSONEncoder().encode(records)
            defaults.set(data, forKey: defaultsKey)
        } catch {
            AppLogger.error("Failed to persist local wallpaper store: \(error.localizedDescription)")
        }
    }
}
