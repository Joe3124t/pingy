import Foundation

final class SettingsService {
    struct PushCapabilities: Decodable {
        let enabled: Bool
        let apnsEnabled: Bool?
        let webPushEnabled: Bool?
        let publicKey: String?
    }

    private let authService: AuthorizedRequester

    init(apiClient _: APIClient, authService: AuthorizedRequester) {
        self.authService = authService
    }

    func getMySettings() async throws -> SettingsResponse {
        try await authService.authorizedRequest(
            Endpoint(path: "users/me/settings", method: .get),
            as: SettingsResponse.self
        )
    }

    func updateProfile(username: String, bio: String) async throws -> User {
        struct Payload: Encodable {
            let username: String
            let bio: String
        }
        let endpoint = try Endpoint.json(
            path: "users/me/profile",
            method: .patch,
            payload: Payload(username: username, bio: bio)
        )
        let response: UserResponse = try await authService.authorizedRequest(endpoint, as: UserResponse.self)
        return response.user
    }

    func changePhoneNumber(
        newPhoneNumber: String,
        currentPassword: String,
        totpCode: String?,
        recoveryCode: String?
    ) async throws -> ChangePhoneResponse {
        struct Payload: Encodable {
            let newPhoneNumber: String
            let currentPassword: String
            let totpCode: String?
            let recoveryCode: String?
        }

        let endpoint = try Endpoint.json(
            path: "users/me/phone",
            method: .patch,
            payload: Payload(
                newPhoneNumber: newPhoneNumber,
                currentPassword: currentPassword,
                totpCode: totpCode,
                recoveryCode: recoveryCode
            )
        )

        return try await authService.authorizedRequest(endpoint, as: ChangePhoneResponse.self)
    }

    func uploadAvatar(
        imageData: Data,
        filename: String = "avatar.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> User {
        var form = MultipartFormData()
        form.appendFile(fieldName: "avatar", fileName: filename, mimeType: mimeType, fileData: imageData)
        form.finalize()

        var endpoint = Endpoint(path: "users/me/avatar", method: .post, body: form.data)
        endpoint.headers["Content-Type"] = "multipart/form-data; boundary=\(form.boundary)"

        let response: UserResponse = try await authService.authorizedRequest(endpoint, as: UserResponse.self)
        return response.user
    }

    func uploadDefaultWallpaper(
        imageData: Data,
        filename: String = "wallpaper.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> User {
        var form = MultipartFormData()
        form.appendFile(fieldName: "wallpaper", fileName: filename, mimeType: mimeType, fileData: imageData)
        form.finalize()

        var endpoint = Endpoint(path: "users/me/chat/wallpaper", method: .post, body: form.data)
        endpoint.headers["Content-Type"] = "multipart/form-data; boundary=\(form.boundary)"

        let response: UserResponse = try await authService.authorizedRequest(endpoint, as: UserResponse.self)
        return response.user
    }

    func updatePrivacy(showOnlineStatus: Bool, readReceiptsEnabled: Bool) async throws -> User {
        struct Payload: Encodable {
            let showOnlineStatus: Bool
            let readReceiptsEnabled: Bool
        }
        let endpoint = try Endpoint.json(
            path: "users/me/privacy",
            method: .patch,
            payload: Payload(showOnlineStatus: showOnlineStatus, readReceiptsEnabled: readReceiptsEnabled)
        )
        let response: UserResponse = try await authService.authorizedRequest(endpoint, as: UserResponse.self)
        return response.user
    }

    func updatePresence(isOnline: Bool) async {
        struct Payload: Encodable {
            let isOnline: Bool
        }

        do {
            let endpoint = try Endpoint.json(
                path: "users/me/presence",
                method: .patch,
                payload: Payload(isOnline: isOnline)
            )
            struct PresenceAck: Decodable { let ok: Bool }
            _ = try await authService.authorizedRequest(endpoint, as: PresenceAck.self)
        } catch {
            AppLogger.error("Presence update failed: \(error.localizedDescription)")
        }
    }

    func fetchPushCapabilities() async -> PushCapabilities? {
        do {
            return try await authService.authorizedRequest(
                Endpoint(path: "users/me/push/public-key", method: .get),
                as: PushCapabilities.self
            )
        } catch {
            AppLogger.error("Push capabilities fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    func updateChat(themeMode: ThemeMode, defaultWallpaperURL: String?) async throws -> User {
        struct Payload: Encodable {
            let themeMode: ThemeMode
            let defaultWallpaperUrl: String?
        }
        let endpoint = try Endpoint.json(
            path: "users/me/chat",
            method: .patch,
            payload: Payload(themeMode: themeMode, defaultWallpaperUrl: defaultWallpaperURL)
        )
        let response: UserResponse = try await authService.authorizedRequest(endpoint, as: UserResponse.self)
        return response.user
    }

    func listBlockedUsers() async throws -> [User] {
        let response: BlockedUsersResponse = try await authService.authorizedRequest(
            Endpoint(path: "users/blocked", method: .get),
            as: BlockedUsersResponse.self
        )
        return response.blockedUsers
    }

    func blockUser(userID: String) async throws -> [User] {
        let endpoint = Endpoint(path: "users/\(userID)/block", method: .post)
        let response: BlockedUsersResponse = try await authService.authorizedRequest(endpoint, as: BlockedUsersResponse.self)
        return response.blockedUsers
    }

    func unblockUser(userID: String) async throws -> [User] {
        let endpoint = Endpoint(path: "users/\(userID)/block", method: .delete)
        let response: BlockedUsersResponse = try await authService.authorizedRequest(endpoint, as: BlockedUsersResponse.self)
        return response.blockedUsers
    }

    func deleteMyAccount() async throws {
        try await authService.authorizedNoContent(
            Endpoint(path: "users/me", method: .delete)
        )
    }

    func upsertPublicKey(_ publicKeyJWK: PublicKeyJWK) async throws {
        struct Payload: Encodable {
            let publicKeyJwk: PublicKeyJWK
            let algorithm: String
        }
        let endpoint = try Endpoint.json(
            path: "crypto/public-key",
            method: .put,
            payload: Payload(publicKeyJwk: publicKeyJWK, algorithm: "ECDH-Curve25519")
        )
        _ = try await authService.authorizedRequest(endpoint, as: UpsertPublicKeyResponse.self)
    }

    func getPublicKey(for userID: String) async throws -> PublicKeyJWK {
        let response: PublicKeyResponse = try await authService.authorizedRequest(
            Endpoint(path: "crypto/public-key/\(userID)", method: .get),
            as: PublicKeyResponse.self
        )
        guard let key = response.key?.publicKeyJwk else {
            throw APIError.server(statusCode: 404, message: "Public key not found")
        }
        return key
    }

    @discardableResult
    func registerAPNsToken(_ tokenHex: String) async -> Bool {
        struct Payload: Encodable {
            struct Subscription: Encodable {
                struct Keys: Encodable {
                    let p256dh: String
                    let auth: String
                }
                let endpoint: String
                let keys: Keys
                let expirationTime: Int?
            }
            let subscription: Subscription
        }

        // APNs endpoint marker consumed by backend push service.
        let endpointURL = "apns://\(tokenHex)"
        let bundleIdentifier = (Bundle.main.bundleIdentifier ?? "com.pingy.messenger")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let topicMarker = bundleIdentifier.isEmpty ? "apns" : "topic:\(bundleIdentifier)"
        let payload = Payload(
            subscription: .init(
                endpoint: endpointURL,
                // `p256dh`/`auth` fields are re-used to carry APNs metadata because the backend endpoint
                // is shared with web push subscriptions.
                keys: .init(p256dh: topicMarker, auth: "ios"),
                expirationTime: nil
            )
        )

        do {
            let endpoint = try Endpoint.json(path: "users/me/push-subscriptions", method: .post, payload: payload)
            struct OK: Decodable { let ok: Bool }
            _ = try await authService.authorizedRequest(endpoint, as: OK.self)
            return true
        } catch {
            AppLogger.error("APNs token registration failed: \(error.localizedDescription)")
            return false
        }
    }
}
