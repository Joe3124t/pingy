import Foundation

final class MessageService {
    private let authService: AuthorizedRequester

    init(apiClient _: APIClient, authService: AuthorizedRequester) {
        self.authService = authService
    }

    func listMessages(
        conversationID: String,
        limit: Int = 60,
        beforeISO: String? = nil
    ) async throws -> [Message] {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let beforeISO {
            queryItems.append(URLQueryItem(name: "before", value: beforeISO))
        }

        let endpoint = Endpoint(
            path: "messages/\(conversationID)",
            method: .get,
            queryItems: queryItems
        )
        let response: MessageListResponse = try await authService.authorizedRequest(endpoint, as: MessageListResponse.self)
        return response.messages
    }

    func sendTextMessage(
        conversationID: String,
        body: String,
        clientID: String,
        replyToMessageID: String?
    ) async throws -> Message {
        struct Payload: Encodable {
            let body: String
            let isEncrypted: Bool
            let clientId: String
            let replyToMessageId: String?
        }

        do {
            let endpoint = try Endpoint.json(
                path: "messages/\(conversationID)",
                method: .post,
                payload: Payload(
                    body: body,
                    isEncrypted: false,
                    clientId: clientID,
                    replyToMessageId: replyToMessageID
                )
            )
            let response: MessageResponse = try await authService.authorizedRequest(endpoint, as: MessageResponse.self)
            return response.message
        } catch let apiError as APIError {
            // Compatibility fallback for older backend payload validators.
            guard case .server(_, let message) = apiError else {
                throw apiError
            }
            let lowered = message.lowercased()
            let shouldRetryWithLegacyPayload =
                lowered.contains("validation failed") ||
                lowered.contains("text body is required") ||
                lowered.contains("invalid body")

            guard shouldRetryWithLegacyPayload else {
                throw apiError
            }

            struct LegacyPayload: Encodable {
                struct LegacyBody: Encodable {
                    let text: String
                }

                let body: LegacyBody
                let isEncrypted: Bool
                let clientId: String
                let replyToMessageId: String?
            }

            let legacyEndpoint = try Endpoint.json(
                path: "messages/\(conversationID)",
                method: .post,
                payload: LegacyPayload(
                    body: .init(text: body),
                    isEncrypted: false,
                    clientId: clientID,
                    replyToMessageId: replyToMessageID
                )
            )
            let legacyResponse: MessageResponse = try await authService.authorizedRequest(legacyEndpoint, as: MessageResponse.self)
            return legacyResponse.message
        }
    }

    func sendEncryptedTextMessage(
        conversationID: String,
        payload: EncryptedPayload,
        clientID: String,
        replyToMessageID: String?
    ) async throws -> Message {
        struct PayloadObjectBody: Encodable {
            let body: JSONValue
            let isEncrypted: Bool
            let clientId: String
            let replyToMessageId: String?
        }

        struct PayloadStringBody: Encodable {
            let body: String
            let isEncrypted: Bool
            let clientId: String
            let replyToMessageId: String?
        }

        struct LegacyEncryptedBody: Encodable {
            let encryptedBody: JSONValue
            let body: String
            let isEncrypted: Bool
            let clientId: String
            let replyToMessageId: String?
        }

        let bodyValue = try JSONValue.fromEncodable(payload)
        let payloadJSONStringData = try JSONEncoder().encode(payload)
        let payloadJSONString = String(data: payloadJSONStringData, encoding: .utf8) ?? "{}"

        do {
            let endpoint = try Endpoint.json(
                path: "messages/\(conversationID)",
                method: .post,
                payload: PayloadObjectBody(
                    body: bodyValue,
                    isEncrypted: true,
                    clientId: clientID,
                    replyToMessageId: replyToMessageID
                )
            )
            let response: MessageResponse = try await authService.authorizedRequest(endpoint, as: MessageResponse.self)
            return response.message
        } catch {
            // Older deployments may require encrypted payload as a JSON string in `body`.
        }

        do {
            let endpoint = try Endpoint.json(
                path: "messages/\(conversationID)",
                method: .post,
                payload: PayloadStringBody(
                    body: payloadJSONString,
                    isEncrypted: true,
                    clientId: clientID,
                    replyToMessageId: replyToMessageID
                )
            )
            let response: MessageResponse = try await authService.authorizedRequest(endpoint, as: MessageResponse.self)
            return response.message
        } catch {
            // Compatibility fallback for deployments using `encryptedBody`.
        }

        let endpoint = try Endpoint.json(
            path: "messages/\(conversationID)",
            method: .post,
            payload: LegacyEncryptedBody(
                encryptedBody: bodyValue,
                body: payloadJSONString,
                isEncrypted: true,
                clientId: clientID,
                replyToMessageId: replyToMessageID
            )
        )
        let response: MessageResponse = try await authService.authorizedRequest(endpoint, as: MessageResponse.self)
        return response.message
    }

    func sendMediaMessage(
        conversationID: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        type: MessageType,
        body: String?,
        voiceDurationMs: Int?,
        clientID: String,
        replyToMessageID: String?
    ) async throws -> Message {
        var form = MultipartFormData()
        form.appendFile(fieldName: "file", fileName: fileName, mimeType: mimeType, fileData: fileData)
        form.appendField(name: "type", value: type.rawValue)
        if let body, !body.isEmpty {
            form.appendField(name: "body", value: body)
        }
        if let voiceDurationMs {
            form.appendField(name: "voiceDurationMs", value: String(voiceDurationMs))
        }
        form.appendField(name: "isEncrypted", value: "false")
        form.appendField(name: "clientId", value: clientID)
        if let replyToMessageID {
            form.appendField(name: "replyToMessageId", value: replyToMessageID)
        }
        form.finalize()

        var endpoint = Endpoint(
            path: "messages/\(conversationID)/upload",
            method: .post,
            body: form.data
        )
        endpoint.headers["Content-Type"] = "multipart/form-data; boundary=\(form.boundary)"

        let response: MessageResponse = try await authService.authorizedRequest(endpoint, as: MessageResponse.self)
        return response.message
    }

    func markSeen(conversationID: String, messageIDs: [String]) async throws {
        struct Payload: Encodable {
            let messageIds: [String]
        }
        let endpoint = try Endpoint.json(
            path: "messages/\(conversationID)/seen",
            method: .post,
            payload: Payload(messageIds: messageIDs)
        )
        _ = try await authService.authorizedRequest(endpoint, as: SeenUpdatesResponse.self)
    }

    func toggleReaction(messageID: String, emoji: String) async throws -> ReactionUpdate {
        struct Payload: Encodable {
            let emoji: String
        }
        let endpoint = try Endpoint.json(
            path: "messages/\(messageID)/reaction",
            method: .put,
            payload: Payload(emoji: emoji)
        )
        let response: ReactionUpdateResponse = try await authService.authorizedRequest(endpoint, as: ReactionUpdateResponse.self)
        return response.update
    }
}
