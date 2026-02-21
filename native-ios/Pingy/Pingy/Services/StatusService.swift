import Foundation

actor StatusService {
    private let authService: AuthorizedRequester
    private let defaults = UserDefaults.standard
    private let cacheKey = "pingy.v3.status.cache"

    private let cacheEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let cacheDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(authService: AuthorizedRequester) {
        self.authService = authService
    }

    func listActiveStories() async -> [StatusStory] {
        do {
            let endpoint = Endpoint(path: "status", method: .get)
            let raw = try await authService.authorizedRawData(endpoint)
            let stories = try decodeStoriesResponse(raw)
            let active = stories.filter { $0.expiresAt > Date() }
            saveCachedStories(active)
            return active
        } catch {
            AppLogger.error("Status list fetch failed, using cache: \(error.localizedDescription)")
            return loadCachedStories().filter { $0.expiresAt > Date() }
        }
    }

    func addTextStory(
        ownerUserID _: String,
        ownerName _: String,
        ownerAvatarURL _: String?,
        text: String,
        backgroundHex: String,
        privacy: StatusPrivacy
    ) async throws {
        struct Payload: Encodable {
            let text: String
            let backgroundHex: String
            let privacy: String
        }

        let endpoint = try Endpoint.json(
            path: "status/text",
            method: .post,
            payload: Payload(
                text: text,
                backgroundHex: backgroundHex,
                privacy: normalizedPrivacy(privacy)
            )
        )

        let raw = try await authService.authorizedRawData(endpoint)
        let created = try decodeStoryResponse(raw)

        guard let created else {
            throw APIError.decodingError
        }

        upsertCachedStory(created)
    }

    func addMediaStory(
        ownerUserID _: String,
        ownerName _: String,
        ownerAvatarURL _: String?,
        mediaData: Data,
        fileExtension: String,
        contentType: StatusContentType,
        privacy: StatusPrivacy
    ) async throws {
        let mimeType = mimeTypeForStatus(fileExtension: fileExtension, contentType: contentType)

        var form = MultipartFormData()
        form.appendFile(
            fieldName: "file",
            fileName: "status-\(UUID().uuidString).\(fileExtension.isEmpty ? defaultExtension(for: contentType) : fileExtension)",
            mimeType: mimeType,
            fileData: mediaData
        )
        form.appendField(name: "contentType", value: contentType.rawValue)
        form.appendField(name: "privacy", value: normalizedPrivacy(privacy))
        form.finalize()

        var endpoint = Endpoint(path: "status/media", method: .post, body: form.data)
        endpoint.headers["Content-Type"] = "multipart/form-data; boundary=\(form.boundary)"

        let raw = try await authService.authorizedRawData(endpoint)
        let created = try decodeStoryResponse(raw)

        guard let created else {
            throw APIError.decodingError
        }

        upsertCachedStory(created)
    }

    func markViewed(storyID: String, viewerID _: String, viewerName _: String) async {
        struct EmptyPayload: Encodable {}

        do {
            let endpoint = try Endpoint.json(
                path: "status/\(storyID)/view",
                method: .post,
                payload: EmptyPayload()
            )
            _ = try await authService.authorizedRawData(endpoint)
        } catch {
            AppLogger.error("Status view marker failed: \(error.localizedDescription)")
        }
    }

    func deleteStory(_ storyID: String) async {
        do {
            let endpoint = Endpoint(path: "status/\(storyID)", method: .delete)
            try await authService.authorizedNoContent(endpoint)
        } catch {
            AppLogger.error("Status delete failed: \(error.localizedDescription)")
        }

        var stories = loadCachedStories()
        stories.removeAll { $0.id == storyID }
        saveCachedStories(stories)
    }

    private func normalizedPrivacy(_ privacy: StatusPrivacy) -> String {
        switch privacy {
        case .contacts:
            return "contacts"
        case .custom:
            return "custom"
        }
    }

    private func mimeTypeForStatus(fileExtension: String, contentType: StatusContentType) -> String {
        let ext = fileExtension.lowercased()

        switch contentType {
        case .image:
            switch ext {
            case "png":
                return "image/png"
            case "webp":
                return "image/webp"
            case "heic", "heif":
                return "image/heic"
            default:
                return "image/jpeg"
            }
        case .video:
            return "video/mp4"
        case .text:
            return "application/octet-stream"
        }
    }

    private func defaultExtension(for contentType: StatusContentType) -> String {
        switch contentType {
        case .image:
            return "jpg"
        case .video:
            return "mp4"
        case .text:
            return "txt"
        }
    }

    private func decodeStoriesResponse(_ raw: Data) throws -> [StatusStory] {
        let response = try JSONDecoder().decode(StatusStoriesResponseDTO.self, from: raw)
        return response.stories.compactMap(mapStatusDTO)
    }

    private func decodeStoryResponse(_ raw: Data) throws -> StatusStory? {
        let response = try JSONDecoder().decode(StatusStoryResponseDTO.self, from: raw)
        guard let dto = response.story else {
            return nil
        }
        return mapStatusDTO(dto)
    }

    private func mapStatusDTO(_ dto: StatusStoryDTO) -> StatusStory? {
        guard let createdAt = parseISODate(dto.createdAt),
              let expiresAt = parseISODate(dto.expiresAt)
        else {
            return nil
        }

        let mappedViewers: [StatusViewer] = dto.viewers.compactMap { item in
            guard let viewedAt = parseISODate(item.viewedAt) else {
                return nil
            }
            return StatusViewer(
                id: item.id,
                name: item.name,
                viewedAt: viewedAt
            )
        }

        return StatusStory(
            id: dto.id,
            ownerUserID: dto.ownerUserID,
            ownerName: dto.ownerName,
            ownerAvatarURL: dto.ownerAvatarURL,
            contentType: dto.contentType,
            text: dto.text,
            mediaURL: dto.mediaURL,
            backgroundHex: dto.backgroundHex,
            privacy: dto.privacy,
            createdAt: createdAt,
            expiresAt: expiresAt,
            viewers: mappedViewers
        )
    }

    private func parseISODate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private func loadCachedStories() -> [StatusStory] {
        guard let data = defaults.data(forKey: cacheKey) else { return [] }
        return (try? cacheDecoder.decode([StatusStory].self, from: data)) ?? []
    }

    private func saveCachedStories(_ stories: [StatusStory]) {
        guard let data = try? cacheEncoder.encode(stories) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func upsertCachedStory(_ story: StatusStory) {
        var stories = loadCachedStories()
        if let index = stories.firstIndex(where: { $0.id == story.id }) {
            stories[index] = story
        } else {
            stories.insert(story, at: 0)
        }

        stories = stories
            .filter { $0.expiresAt > Date() }
            .sorted { $0.createdAt > $1.createdAt }

        saveCachedStories(stories)
    }
}

private struct StatusStoriesResponseDTO: Decodable {
    let stories: [StatusStoryDTO]
}

private struct StatusStoryResponseDTO: Decodable {
    let story: StatusStoryDTO?
}

private struct StatusStoryDTO: Decodable {
    let id: String
    let ownerUserID: String
    let ownerName: String
    let ownerAvatarURL: String?
    let contentType: StatusContentType
    let text: String?
    let mediaURL: String?
    let backgroundHex: String?
    let privacy: StatusPrivacy
    let createdAt: String
    let expiresAt: String
    let viewers: [StatusViewerDTO]
}

private struct StatusViewerDTO: Decodable {
    let id: String
    let name: String
    let viewedAt: String
}
