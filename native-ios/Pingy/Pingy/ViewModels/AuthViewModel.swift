import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode {
        case login
        case register
        case forgotPassword
        case confirmReset
    }

    @Published var mode: Mode = .login
    @Published var email = ""
    @Published var password = ""
    @Published var username = ""
    @Published var resetCode = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let authService: AuthService
    private let cryptoService: E2EECryptoService
    private let settingsService: SettingsService

    init(authService: AuthService, cryptoService: E2EECryptoService, settingsService: SettingsService) {
        self.authService = authService
        self.cryptoService = cryptoService
        self.settingsService = settingsService
    }

    func submit() async {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            switch mode {
            case .login:
                let user = try await authService.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                try await bootstrapCrypto(userID: user.id)
            case .register:
                let user = try await authService.register(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                try await bootstrapCrypto(userID: user.id)
            case .forgotPassword:
                let message = try await authService.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
                infoMessage = message
                mode = .confirmReset
            case .confirmReset:
                guard newPassword == confirmPassword else {
                    throw APIError.server(statusCode: 400, message: "Passwords do not match")
                }
                let message = try await authService.confirmPasswordReset(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    code: resetCode.trimmingCharacters(in: .whitespacesAndNewlines),
                    newPassword: newPassword
                )
                infoMessage = message
                mode = .login
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func switchMode(_ mode: Mode) {
        self.mode = mode
        errorMessage = nil
        infoMessage = nil
    }

    private func bootstrapCrypto(userID: String) async throws {
        let publicKey = try await cryptoService.ensureIdentity(for: userID)
        try await settingsService.upsertPublicKey(publicKey)
    }
}
