import Foundation

enum LoginFlowResult {
    case authenticated(User)
    case requiresTotp(challengeToken: String, userHint: AuthUserHint?, message: String?)
}

@MainActor
final class AuthService: ObservableObject, AuthorizedRequester {
    @Published private(set) var isRestoringSession = false

    let sessionStore: SessionStore
    private let apiClient: APIClient
    private let deviceIdentity = DeviceIdentityStore.shared

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

    func requestOTP(phoneNumber: String, purpose: String = "register") async throws -> OTPRequestResponse {
        struct Payload: Encodable {
            let phoneNumber: String
            let purpose: String
        }

        let candidatePaths = [
            "auth/phone/request-otp",
            "auth/request-otp",
            "auth/phone/request",
            "phone/request-otp",
            "phone/request"
        ]

        return try await requestWithPathFallback(
            candidatePaths: candidatePaths,
            payload: Payload(phoneNumber: phoneNumber, purpose: purpose)
        )
    }

    func verifyOTP(phoneNumber: String, code: String, purpose: String = "register") async throws -> OTPVerifyResponse {
        struct Payload: Encodable {
            let phoneNumber: String
            let code: String
            let purpose: String
        }

        let candidatePaths = [
            "auth/phone/verify-otp",
            "auth/verify-otp",
            "auth/phone/verify",
            "phone/verify-otp",
            "phone/verify"
        ]

        return try await requestWithPathFallback(
            candidatePaths: candidatePaths,
            payload: Payload(phoneNumber: phoneNumber, code: code, purpose: purpose)
        )
    }

    func login(phoneNumber: String, password: String) async throws -> LoginFlowResult {
        struct LoginPayload: Encodable {
            let phoneNumber: String
            let password: String
            let deviceId: String
        }
        let endpoint = try Endpoint.json(
            path: "auth/login",
            method: .post,
            payload: LoginPayload(
                phoneNumber: phoneNumber,
                password: password,
                deviceId: deviceIdentity.currentDeviceID()
            )
        )
        let response: LoginResponse = try await apiClient.request(endpoint)

        if response.requiresTotp == true {
            guard let challengeToken = response.challengeToken, !challengeToken.isEmpty else {
                throw APIError.server(statusCode: 400, message: "Two-step challenge is missing")
            }
            return .requiresTotp(
                challengeToken: challengeToken,
                userHint: response.userHint,
                message: response.message
            )
        }

        guard let user = response.user, let tokens = response.tokens else {
            throw APIError.decodingError
        }

        sessionStore.update(user: user, tokens: tokens)
        return .authenticated(user)
    }

    func verifyTotpLogin(
        challengeToken: String,
        code: String?,
        recoveryCode: String?
    ) async throws -> User {
        struct Payload: Encodable {
            let challengeToken: String
            let code: String?
            let recoveryCode: String?
        }

        let response: TotpLoginPayloadResponse = try await requestWithPathFallback(
            candidatePaths: [
                "auth/totp/login/verify",
                "auth/login/totp/verify"
            ],
            payload: Payload(
                challengeToken: challengeToken,
                code: code?.trimmingCharacters(in: .whitespacesAndNewlines),
                recoveryCode: recoveryCode?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        sessionStore.update(user: response.user, tokens: response.tokens)
        return response.user
    }

    func register(
        verificationToken: String,
        displayName: String,
        password: String,
        bio: String = ""
    ) async throws -> User {
        struct RegisterPayload: Encodable {
            let verificationToken: String
            let displayName: String
            let bio: String
            let password: String
            let deviceId: String
        }
        let endpoint = try Endpoint.json(
            path: "auth/register",
            method: .post,
            payload: RegisterPayload(
                verificationToken: verificationToken,
                displayName: displayName,
                bio: bio,
                password: password,
                deviceId: deviceIdentity.currentDeviceID()
            )
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

    func requestPasswordReset(phoneNumber: String) async throws -> String {
        struct Payload: Encodable { let phoneNumber: String }
        let endpoint = try Endpoint.json(
            path: "auth/forgot-password/request",
            method: .post,
            payload: Payload(phoneNumber: phoneNumber)
        )
        let response: GenericMessageResponse = try await apiClient.request(endpoint)
        return response.message
    }

    func confirmPasswordReset(phoneNumber: String, code: String, newPassword: String) async throws -> String {
        struct Payload: Encodable {
            let phoneNumber: String
            let code: String
            let newPassword: String
            let deviceId: String
        }
        let endpoint = try Endpoint.json(
            path: "auth/forgot-password/confirm",
            method: .post,
            payload: Payload(
                phoneNumber: phoneNumber,
                code: code,
                newPassword: newPassword,
                deviceId: deviceIdentity.currentDeviceID()
            )
        )
        let response: GenericMessageResponse = try await apiClient.request(endpoint)
        return response.message
    }

    func getTotpStatus() async throws -> TotpStatusResponse {
        try await authorizedRequest(
            Endpoint(path: "auth/totp/status", method: .get),
            as: TotpStatusResponse.self
        )
    }

    func startTotpSetup() async throws -> TotpSetupStartResponse {
        let endpoint = try Endpoint.json(path: "auth/totp/setup/start", method: .post, payload: EmptyBody())
        return try await authorizedRequest(endpoint, as: TotpSetupStartResponse.self)
    }

    func verifyTotpSetup(code: String) async throws -> TotpSetupVerifyResponse {
        struct Payload: Encodable {
            let code: String
        }

        let endpoint = try Endpoint.json(
            path: "auth/totp/setup/verify",
            method: .post,
            payload: Payload(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        return try await authorizedRequest(endpoint, as: TotpSetupVerifyResponse.self)
    }

    func disableTotp(code: String?, recoveryCode: String?) async throws -> String {
        struct Payload: Encodable {
            let code: String?
            let recoveryCode: String?
        }

        let endpoint = try Endpoint.json(
            path: "auth/totp/disable",
            method: .post,
            payload: Payload(
                code: code?.trimmingCharacters(in: .whitespacesAndNewlines),
                recoveryCode: recoveryCode?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        let response: GenericMessageResponse = try await authorizedRequest(endpoint, as: GenericMessageResponse.self)
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

    private func requestWithPathFallback<T: Decodable, P: Encodable>(
        candidatePaths: [String],
        payload: P
    ) async throws -> T {
        var lastError: APIError?

        for (index, path) in candidatePaths.enumerated() {
            do {
                let endpoint = try Endpoint.json(path: path, method: .post, payload: payload)
                return try await apiClient.request(endpoint)
            } catch let apiError as APIError {
                if shouldTryNextPath(apiError: apiError, currentIndex: index, totalCount: candidatePaths.count) {
                    AppLogger.debug("Retrying auth endpoint with fallback path: \(path)")
                    lastError = apiError
                    continue
                }
                throw apiError
            }
        }

        throw lastError ?? APIError.server(statusCode: 404, message: "Route not found")
    }

    private func shouldTryNextPath(apiError: APIError, currentIndex: Int, totalCount: Int) -> Bool {
        guard currentIndex < totalCount - 1 else {
            return false
        }

        switch apiError {
        case .server(let statusCode, let message):
            let normalized = message.lowercased()
            return statusCode == 404 || normalized.contains("route not found")
        default:
            return false
        }
    }
}

private struct EmptyBody: Encodable {}
