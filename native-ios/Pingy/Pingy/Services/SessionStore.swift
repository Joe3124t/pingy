import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var currentUser: User?
    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?

    var isAuthenticated: Bool {
        currentUser != nil && (!((accessToken ?? "").isEmpty) || !((refreshToken ?? "").isEmpty))
    }

    private let userDefaults = UserDefaults.standard
    private let keychain = KeychainStore.shared
    private let sessionMigrationVersion = 3

    private enum Keys {
        static let accessToken = "pingy.session.accessToken"
        static let refreshToken = "pingy.session.refreshToken"
        static let accessTokenFallback = "pingy.session.accessToken.fallback"
        static let refreshTokenFallback = "pingy.session.refreshToken.fallback"
        static let currentUser = "pingy.session.currentUser"
        static let migrationVersion = "pingy.security.migrationVersion"
    }

    private struct AccessTokenClaims: Decodable {
        let sub: String
        let username: String?
        let phoneNumber: String?
        let deviceId: String?
    }

    init() {
        runSessionMigrationIfNeeded()
        restore()
    }

    func update(user: User, tokens: AuthTokens) {
        currentUser = user
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken

        do {
            try keychain.set(tokens.accessToken, for: Keys.accessToken)
            try keychain.set(tokens.refreshToken, for: Keys.refreshToken)
        } catch {
            AppLogger.error("Failed to persist tokens in keychain: \(error.localizedDescription)")
        }
        userDefaults.set(tokens.accessToken, forKey: Keys.accessTokenFallback)
        userDefaults.set(tokens.refreshToken, forKey: Keys.refreshTokenFallback)

        do {
            let data = try JSONEncoder().encode(user)
            userDefaults.set(data, forKey: Keys.currentUser)
        } catch {
            AppLogger.error("Failed to persist current user: \(error.localizedDescription)")
        }
    }

    func updateAccessToken(_ token: String) {
        accessToken = token
        do {
            try keychain.set(token, for: Keys.accessToken)
        } catch {
            AppLogger.error("Failed to update access token: \(error.localizedDescription)")
        }
        userDefaults.set(token, forKey: Keys.accessTokenFallback)
    }

    func clear() {
        currentUser = nil
        accessToken = nil
        refreshToken = nil

        do {
            try keychain.delete(Keys.accessToken)
            try keychain.delete(Keys.refreshToken)
        } catch {
            AppLogger.error("Failed to clear keychain session: \(error.localizedDescription)")
        }

        userDefaults.removeObject(forKey: Keys.accessTokenFallback)
        userDefaults.removeObject(forKey: Keys.refreshTokenFallback)
        userDefaults.removeObject(forKey: Keys.currentUser)
    }

    private func restore() {
        do {
            accessToken = try keychain.string(for: Keys.accessToken)
            refreshToken = try keychain.string(for: Keys.refreshToken)
        } catch {
            AppLogger.error("Failed to restore tokens from keychain: \(error.localizedDescription)")
        }

        if (accessToken ?? "").isEmpty {
            accessToken = userDefaults.string(forKey: Keys.accessTokenFallback)
        }

        if (refreshToken ?? "").isEmpty {
            refreshToken = userDefaults.string(forKey: Keys.refreshTokenFallback)
        }

        if let userData = userDefaults.data(forKey: Keys.currentUser) {
            currentUser = try? JSONDecoder().decode(User.self, from: userData)
        }

        if currentUser == nil {
            restoreUserFromAccessTokenIfNeeded()
        }
    }

    private func restoreUserFromAccessTokenIfNeeded() {
        guard let accessToken, !accessToken.isEmpty else { return }
        guard let claims = Self.decodeClaims(from: accessToken) else { return }

        let fallbackUsername = claims.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUsername: String
        if let fallbackUsername, !fallbackUsername.isEmpty {
            resolvedUsername = fallbackUsername
        } else if let phone = claims.phoneNumber, !phone.isEmpty {
            resolvedUsername = phone
        } else {
            resolvedUsername = "Pingy User"
        }

        let fallbackUser = User(
            id: claims.sub,
            username: resolvedUsername,
            phoneNumber: claims.phoneNumber,
            email: nil,
            avatarUrl: nil,
            bio: nil,
            isOnline: nil,
            lastSeen: nil,
            lastLoginAt: nil,
            deviceId: claims.deviceId,
            showOnlineStatus: nil,
            readReceiptsEnabled: nil,
            themeMode: nil,
            defaultWallpaperUrl: nil,
            totpEnabled: nil
        )

        currentUser = fallbackUser
        if let data = try? JSONEncoder().encode(fallbackUser) {
            userDefaults.set(data, forKey: Keys.currentUser)
        }
    }

    private static func decodeClaims(from jwt: String) -> AccessTokenClaims? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
        payload = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONDecoder().decode(AccessTokenClaims.self, from: data)
    }

    private func runSessionMigrationIfNeeded() {
        let appliedVersion = userDefaults.integer(forKey: Keys.migrationVersion)

        guard appliedVersion < sessionMigrationVersion else {
            return
        }

        // Keep existing keychain/session data across app updates.
        userDefaults.set(sessionMigrationVersion, forKey: Keys.migrationVersion)
    }
}
