import Foundation

@MainActor
final class AuthService: ObservableObject, AuthorizedRequester {
    @Published private(set) var isRestoringSession = false

    let sessionStore: SessionStore
    private let apiClient: APIClient

    init(apiClient: APIClient, sessionStore: SessionStore) {
        self.apiClient = apiClient
        self.sessionStore = sessionStore
    }

    func restoreSession() async {
        guard sessionStore.currentUser != nil else { return }
        guard sessionStore.refreshToken != nil else {
            sessionStore.clear()
            return
        }

        isRestoringSession = true
        defer { isRestoringSession = false }

        do {
            _ = try await validAccessToken(forceRefresh: true)
            let me: MeResponse = try await authorizedRequest(
                Endpoint(path: "auth/me", method: .get),
                as: MeResponse.self
            )
            let tokens = AuthTokens(
                accessToken: sessionStore.accessToken ?? "",
                refreshToken: sessionStore.refreshToken ?? ""
            )
            sessionStore.update(user: me.user, tokens: tokens)
        } catch {
            AppLogger.error("Session restore failed: \(error.localizedDescription)")
            sessionStore.clear()
        }
    }

    func login(email: String, password: String) async throws -> User {
        struct LoginPayload: Encodable {
            let email: String
            let password: String
        }
        let endpoint = try Endpoint.json(
            path: "auth/login",
            method: .post,
            payload: LoginPayload(email: email, password: password)
        )
        let response: AuthResponse = try await apiClient.request(endpoint)
        sessionStore.update(user: response.user, tokens: response.tokens)
        return response.user
    }

    func register(username: String, email: String, password: String) async throws -> User {
        struct RegisterPayload: Encodable {
            let username: String
            let email: String
            let password: String
        }
        let endpoint = try Endpoint.json(
            path: "auth/register",
            method: .post,
            payload: RegisterPayload(username: username, email: email, password: password)
        )
        let response: AuthResponse = try await apiClient.request(endpoint)
        sessionStore.update(user: response.user, tokens: response.tokens)
        return response.user
    }

    func logout() async {
        guard let refreshToken = sessionStore.refreshToken else {
            sessionStore.clear()
            return
        }

        struct LogoutPayload: Encodable {
            let refreshToken: String
        }

        do {
            let endpoint = try Endpoint.json(
                path: "auth/logout",
                method: .post,
                payload: LogoutPayload(refreshToken: refreshToken)
            )
            try await apiClient.requestNoContent(endpoint)
        } catch {
            AppLogger.error("Logout request failed: \(error.localizedDescription)")
        }

        sessionStore.clear()
    }

    func requestPasswordReset(email: String) async throws -> String {
        struct Payload: Encodable { let email: String }
        let endpoint = try Endpoint.json(path: "auth/forgot-password/request", method: .post, payload: Payload(email: email))
        let response: GenericMessageResponse = try await apiClient.request(endpoint)
        return response.message
    }

    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws -> String {
        struct Payload: Encodable {
            let email: String
            let code: String
            let newPassword: String
        }
        let endpoint = try Endpoint.json(
            path: "auth/forgot-password/confirm",
            method: .post,
            payload: Payload(email: email, code: code, newPassword: newPassword)
        )
        let response: GenericMessageResponse = try await apiClient.request(endpoint)
        return response.message
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let currentAccess = sessionStore.accessToken, !currentAccess.isEmpty else {
            throw APIError.unauthorized
        }
        if !forceRefresh && !JWTUtilities.isExpiringSoon(token: currentAccess) {
            return currentAccess
        }

        guard let refreshToken = sessionStore.refreshToken else {
            throw APIError.unauthorized
        }

        struct RefreshPayload: Encodable {
            let refreshToken: String
        }

        let endpoint = try Endpoint.json(path: "auth/refresh", method: .post, payload: RefreshPayload(refreshToken: refreshToken))
        let response: AuthResponse = try await apiClient.request(endpoint)
        sessionStore.update(user: response.user, tokens: response.tokens)
        return response.tokens.accessToken
    }

    func authorizedRequest<T: Decodable>(_ endpoint: Endpoint, as: T.Type) async throws -> T {
        do {
            let token = try await validAccessToken()
            return try await apiClient.request(endpoint, accessToken: token)
        } catch APIError.unauthorized {
            let token = try await validAccessToken(forceRefresh: true)
            return try await apiClient.request(endpoint, accessToken: token)
        }
    }

    func authorizedNoContent(_ endpoint: Endpoint) async throws {
        do {
            let token = try await validAccessToken()
            try await apiClient.requestNoContent(endpoint, accessToken: token)
        } catch APIError.unauthorized {
            let token = try await validAccessToken(forceRefresh: true)
            try await apiClient.requestNoContent(endpoint, accessToken: token)
        }
    }

    func authorizedRawData(_ endpoint: Endpoint) async throws -> Data {
        do {
            let token = try await validAccessToken()
            return try await apiClient.requestRawData(endpoint, accessToken: token)
        } catch APIError.unauthorized {
            let token = try await validAccessToken(forceRefresh: true)
            return try await apiClient.requestRawData(endpoint, accessToken: token)
        }
    }
}
