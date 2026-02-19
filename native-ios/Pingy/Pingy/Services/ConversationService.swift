import Foundation

final class ConversationService {
    private let authService: AuthorizedRequester

    init(apiClient _: APIClient, authService: AuthorizedRequester) {
        self.authService = authService
    }

    func listConversations() async throws -> [Conversation] {
        let response: ConversationListResponse = try await authService.authorizedRequest(
            Endpoint(path: "conversations", method: .get),
            as: ConversationListResponse.self
        )
        return response.conversations
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
        blurIntensity: Int
    ) async throws -> ConversationWallpaperEvent {
        struct Response: Decodable {
            struct Settings: Decodable {
                let conversationId: String
                let wallpaperUrl: String?
                let blurIntensity: Int
            }
            let settings: Settings
        }

        var form = MultipartFormData()
        form.appendField(name: "blurIntensity", value: String(blurIntensity))
        form.appendFile(
            fieldName: "wallpaper",
            fileName: fileName,
            mimeType: "image/jpeg",
            fileData: imageData
        )
        form.finalize()

        var endpoint = Endpoint(
            path: "conversations/\(conversationID)/wallpaper/upload",
            method: .post,
            body: form.data
        )
        endpoint.headers["Content-Type"] = "multipart/form-data; boundary=\(form.boundary)"

        let response: Response = try await authService.authorizedRequest(endpoint, as: Response.self)
        return ConversationWallpaperEvent(
            conversationId: response.settings.conversationId,
            wallpaperUrl: response.settings.wallpaperUrl,
            blurIntensity: response.settings.blurIntensity
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

        struct Response: Decodable {
            struct Settings: Decodable {
                let conversationId: String
                let wallpaperUrl: String?
                let blurIntensity: Int
            }
            let settings: Settings
        }

        let endpoint = try Endpoint.json(
            path: "conversations/\(conversationID)/wallpaper",
            method: .put,
            payload: Payload(wallpaperUrl: wallpaperURL, blurIntensity: blurIntensity)
        )
        let response: Response = try await authService.authorizedRequest(endpoint, as: Response.self)
        return ConversationWallpaperEvent(
            conversationId: response.settings.conversationId,
            wallpaperUrl: response.settings.wallpaperUrl,
            blurIntensity: response.settings.blurIntensity
        )
    }

    func resetConversationWallpaper(conversationID: String) async throws {
        let endpoint = Endpoint(
            path: "conversations/\(conversationID)/wallpaper",
            method: .delete
        )
        try await authService.authorizedNoContent(endpoint)
    }
}
