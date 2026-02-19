import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var currentUser: User?
    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?

    var isAuthenticated: Bool {
        currentUser != nil && !(accessToken ?? "").isEmpty && !(refreshToken ?? "").isEmpty
    }

    private let userDefaults = UserDefaults.standard
    private let keychain = KeychainStore.shared

    private enum Keys {
        static let accessToken = "pingy.session.accessToken"
        static let refreshToken = "pingy.session.refreshToken"
        static let currentUser = "pingy.session.currentUser"
    }

    init() {
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

        userDefaults.removeObject(forKey: Keys.currentUser)
    }

    private func restore() {
        do {
            accessToken = try keychain.string(for: Keys.accessToken)
            refreshToken = try keychain.string(for: Keys.refreshToken)
        } catch {
            AppLogger.error("Failed to restore tokens from keychain: \(error.localizedDescription)")
        }

        if let userData = userDefaults.data(forKey: Keys.currentUser) {
            currentUser = try? JSONDecoder().decode(User.self, from: userData)
        }
    }
}
