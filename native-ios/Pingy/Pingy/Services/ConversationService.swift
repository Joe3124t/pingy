import Foundation

final class ConversationService {
    private let authService: AuthorizedRequester
    private let wallpaperStore = ConversationWallpaperStore.shared

    private struct ConversationWallpaperSettingsResponse: Decodable {
        struct Settings: Decodable {
            let conversationId: String?
            let wallpaperUrl: String?
            let blurIntensity: Int?
        }

        let settings: Settings?
    }

    init(apiClient _: APIClient, authService: AuthorizedRequester) {
        self.authService = authService
    }

    func listConversations() async throws -> [Conversation] {
        let response: ConversationListResponse = try await authService.authorizedRequest(
            Endpoint(path: "conversations", method: .get),
            as: ConversationListResponse.self
        )
        return await wallpaperStore.applyOverrides(to: response.conversations)
    }

    func searchUsers(query: String, limit: Int = 15) async throws -> [User] {
        struct SearchUsersResponse: Decodable {
            let users: [User]
        }

        let endpoint = Endpoint(
            path: "users",
            method: .get,
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )

        let response: SearchUsersResponse = try await authService.authorizedRequest(endpoint, as: SearchUsersResponse.self)
        return response.users
    }

    func createDirectConversation(recipientID: String) async throws -> Conversation {
        struct Payload: Encodable {
            let recipientId: String
        }
        let endpoint = try Endpoint.json(
            path: "conversations/direct",
            method: .post,
            payload: Payload(recipientId: recipientID)
        )
        let response: ConversationResponse = try await authService.authorizedRequest(endpoint, as: ConversationResponse.self)
        return response.conversation
    }

    func deleteConversation(conversationID: String, scope: String) async throws {
        let endpoint = Endpoint(
            path: "conversations/\(conversationID)",
            method: .delete,
            queryItems: [URLQueryItem(name: "scope", value: scope)]
        )
        try await authService.authorizedNoContent(endpoint)
    }

    func uploadConversationWallpaper(
        conversationID: String,
        imageData: Data,
        fileName: String,
        mimeType: String,
        blurIntensity: Int
    ) async throws -> ConversationWallpaperEvent {
        var form = MultipartFormData()
        form.appendFile(fieldName: "wallpaper", fileName: fileName, mimeType: mimeType, fileData: imageData)
        form.appendField(name: "blurIntensity", value: String(max(0, min(20, blurIntensity))))
        form.finalize()

        var endpoint = Endpoint(
            path: "conversations/\(conversationID)/wallpaper/upload",
            method: .post,
            body: form.data
        )
        endpoint.headers["Content-Type"] = "multipart/form-data; boundary=\(form.boundary)"

        let response: ConversationWallpaperSettingsResponse = try await authService.authorizedRequest(
            endpoint,
            as: ConversationWallpaperSettingsResponse.self
        )

        let settings = response.settings
        let resolvedConversationID = settings?.conversationId ?? conversationID
        let wallpaperUrl = settings?.wallpaperUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBlur = max(0, min(20, settings?.blurIntensity ?? blurIntensity))

        if let wallpaperUrl, !wallpaperUrl.isEmpty {
            if let resolvedURL = MediaURLResolver.resolve(wallpaperUrl) {
                await RemoteImageStore.shared.primeImage(data: imageData, for: resolvedURL)
            }
            return await wallpaperStore.saveRemoteURL(
                conversationId: resolvedConversationID,
                wallpaperURL: wallpaperUrl,
                blurIntensity: normalizedBlur
            )
        }

        try await wallpaperStore.reset(conversationId: resolvedConversationID)
        return ConversationWallpaperEvent(
            conversationId: resolvedConversationID,
            wallpaperUrl: nil,
            blurIntensity: 0
        )
    }

    func updateConversationWallpaper(
        conversationID: String,
        wallpaperURL: String?,
        blurIntensity: Int
    ) async throws -> ConversationWallpaperEvent {
        struct Payload: Encodable {
            let wallpaperUrl: String?
            let blurIntensity: Int
        }

        let normalizedBlur = max(0, min(20, blurIntensity))
        let trimmed = wallpaperURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = Payload(
            wallpaperUrl: (trimmed?.isEmpty == false) ? trimmed : nil,
            blurIntensity: normalizedBlur
        )
        let endpoint = try Endpoint.json(
            path: "conversations/\(conversationID)/wallpaper",
            method: .put,
            payload: payload
        )

        let response: ConversationWallpaperSettingsResponse = try await authService.authorizedRequest(
            endpoint,
            as: ConversationWallpaperSettingsResponse.self
        )

        let settings = response.settings
        let resolvedConversationID = settings?.conversationId ?? conversationID
        let responseWallpaper = settings?.wallpaperUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        let responseBlur = max(0, min(20, settings?.blurIntensity ?? normalizedBlur))

        guard let responseWallpaper, !responseWallpaper.isEmpty else {
            try await wallpaperStore.reset(conversationId: resolvedConversationID)
            return ConversationWallpaperEvent(
                conversationId: resolvedConversationID,
                wallpaperUrl: nil,
                blurIntensity: 0
            )
        }

        return await wallpaperStore.saveRemoteURL(
            conversationId: resolvedConversationID,
            wallpaperURL: responseWallpaper,
            blurIntensity: responseBlur
        )
    }

    func resetConversationWallpaper(conversationID: String) async throws {
        try await authService.authorizedNoContent(
            Endpoint(path: "conversations/\(conversationID)/wallpaper", method: .delete)
        )
        try await wallpaperStore.reset(conversationId: conversationID)
    }
}
