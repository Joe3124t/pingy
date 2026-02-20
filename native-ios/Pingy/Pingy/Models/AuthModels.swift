import Foundation

struct AuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
}

struct AuthResponse: Codable {
    let user: User
    let tokens: AuthTokens
}

struct MeResponse: Codable {
    let user: User
}

struct GenericMessageResponse: Codable {
    let message: String
}

struct SignupStartResponse: Codable {
    let message: String
    let challengeToken: String
    let secret: String
    let otpAuthUrl: String
    let issuer: String
    let accountName: String
}

struct SignupVerifyResponse: Codable {
    let message: String
    let registrationToken: String
}

struct AuthUserHint: Codable, Equatable {
    let id: String
    let username: String
    let phoneMasked: String
}

struct LoginResponse: Codable {
    let user: User?
    let tokens: AuthTokens?
    let requiresTotp: Bool?
    let challengeToken: String?
    let userHint: AuthUserHint?
    let message: String?
}

struct TotpLoginPayloadResponse: Codable {
    let user: User
    let tokens: AuthTokens
}

struct TotpStatusResponse: Codable {
    let enabled: Bool
    let pending: Bool
    let pendingExpiresAt: String?
    let recoveryCodesAvailable: Int
    let issuer: String
    let isServerEnabled: Bool
}

struct TotpSetupStartResponse: Codable {
    let secret: String
    let otpAuthUrl: String
    let issuer: String
    let accountName: String
    let expiresAt: String
}

struct TotpSetupVerifyResponse: Codable {
    let message: String
    let recoveryCodes: [String]
}
