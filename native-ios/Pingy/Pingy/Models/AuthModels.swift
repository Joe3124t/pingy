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

struct OTPRequestResponse: Codable {
    let message: String
}

struct OTPVerifyResponse: Codable {
    let verificationToken: String
    let isRegistered: Bool
}
