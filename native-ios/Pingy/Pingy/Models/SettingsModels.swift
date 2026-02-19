import Foundation

struct SettingsResponse: Codable {
    let user: User
    let blockedUsers: [User]
}

struct BlockedUsersResponse: Codable {
    let blockedUsers: [User]
}

struct UserResponse: Codable {
    let user: User
}

struct PushPublicKeyResponse: Codable {
    let enabled: Bool
    let publicKey: String?
}

struct PublicKeyRecord: Codable, Equatable {
    let userId: String?
    let publicKeyJwk: PublicKeyJWK
    let algorithm: String?
    let createdAt: String?
    let updatedAt: String?
}

struct PublicKeyResponse: Codable {
    let key: PublicKeyRecord?
}

struct UpsertPublicKeyResponse: Codable {
    let key: PublicKeyRecord
}
