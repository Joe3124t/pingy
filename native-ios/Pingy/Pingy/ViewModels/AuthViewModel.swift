import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode {
        case phoneEntry
        case otpVerify
        case registerProfile
        case loginPassword
        case forgotPasswordRequest
        case forgotPasswordConfirm
    }

    @Published var mode: Mode = .phoneEntry
    @Published var phoneNumber = ""
    @Published var otpCode = ""
    @Published var displayName = ""
    @Published var bio = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var newPassword = ""
    @Published var resetCode = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var debugCodeHint: String?

    private var registrationVerificationToken: String?
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
            case .phoneEntry:
                let response = try await authService.requestOTP(
                    phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                    purpose: "register"
                )
                infoMessage = response.message
                debugCodeHint = response.debugCode
                mode = .otpVerify

            case .otpVerify:
                let response = try await authService.verifyOTP(
                    phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                    code: otpCode.trimmingCharacters(in: .whitespacesAndNewlines),
                    purpose: "register"
                )
                registrationVerificationToken = response.verificationToken
                if response.isRegistered {
                    mode = .loginPassword
                } else {
                    mode = .registerProfile
                }

            case .registerProfile:
                guard password == confirmPassword else {
                    throw APIError.server(statusCode: 400, message: "Passwords do not match")
                }

                guard let verificationToken = registrationVerificationToken else {
                    throw APIError.server(statusCode: 400, message: "Verify OTP code first")
                }

                let user = try await authService.register(
                    verificationToken: verificationToken,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    bio: bio.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                try await bootstrapCrypto(userID: user.id)

            case .loginPassword:
                let user = try await authService.login(
                    phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                try await bootstrapCrypto(userID: user.id)

            case .forgotPasswordRequest:
                let message = try await authService.requestPasswordReset(
                    phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                infoMessage = message
                mode = .forgotPasswordConfirm

            case .forgotPasswordConfirm:
                guard newPassword == confirmPassword else {
                    throw APIError.server(statusCode: 400, message: "Passwords do not match")
                }
                let message = try await authService.confirmPasswordReset(
                    phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                    code: resetCode.trimmingCharacters(in: .whitespacesAndNewlines),
                    newPassword: newPassword
                )
                infoMessage = message
                mode = .loginPassword
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func moveTo(_ newMode: Mode) {
        mode = newMode
        errorMessage = nil
        infoMessage = nil
    }

    func resetToPhoneEntry() {
        mode = .phoneEntry
        registrationVerificationToken = nil
        otpCode = ""
        password = ""
        confirmPassword = ""
        newPassword = ""
        resetCode = ""
        debugCodeHint = nil
        errorMessage = nil
        infoMessage = nil
    }

    private func bootstrapCrypto(userID: String) async throws {
        let publicKey = try await cryptoService.ensureIdentity(for: userID)
        try await settingsService.upsertPublicKey(publicKey)
    }
}
