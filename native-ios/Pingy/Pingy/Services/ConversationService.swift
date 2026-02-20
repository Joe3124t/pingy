import Foundation

final class ConversationService {
    private let authService: AuthorizedRequester
    private let wallpaperStore = ConversationWallpaperStore.shared

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
        _ = mimeType
        return try await wallpaperStore.saveImage(
            conversationId: conversationID,
            imageData: imageData,
            fileName: fileName,
            blurIntensity: blurIntensity
        )
    }

    func updateConversationWallpaper(
        conversationID: String,
        wallpaperURL: String?,
        blurIntensity: Int
    ) async throws -> ConversationWallpaperEvent {
        let trimmed = wallpaperURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            try await wallpaperStore.reset(conversationId: conversationID)
            return ConversationWallpaperEvent(
                conversationId: conversationID,
                wallpaperUrl: nil,
                blurIntensity: 0
            )
        }

        return await wallpaperStore.saveRemoteURL(
            conversationId: conversationID,
            wallpaperURL: trimmed,
            blurIntensity: blurIntensity
        )
    }

    func resetConversationWallpaper(conversationID: String) async throws {
        try await wallpaperStore.reset(conversationId: conversationID)
    }
}
