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
            let normalizedPhone = normalizedPhoneNumber(phoneNumber)

            switch mode {
            case .phoneEntry:
                let response = try await authService.requestOTP(
                    phoneNumber: normalizedPhone,
                    purpose: "register"
                )
                infoMessage = response.message
                mode = .otpVerify

            case .otpVerify:
                let response = try await authService.verifyOTP(
                    phoneNumber: normalizedPhone,
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
                    phoneNumber: normalizedPhone,
                    password: password
                )
                try await bootstrapCrypto(userID: user.id)

            case .forgotPasswordRequest:
                let message = try await authService.requestPasswordReset(
                    phoneNumber: normalizedPhone
                )
                infoMessage = message
                mode = .forgotPasswordConfirm

            case .forgotPasswordConfirm:
                guard newPassword == confirmPassword else {
                    throw APIError.server(statusCode: 400, message: "Passwords do not match")
                }
                let message = try await authService.confirmPasswordReset(
                    phoneNumber: normalizedPhone,
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
        errorMessage = nil
        infoMessage = nil
    }

    private func bootstrapCrypto(userID: String) async throws {
        let publicKey = try await cryptoService.ensureIdentity(for: userID)
        try await settingsService.upsertPublicKey(publicKey)
    }

    private func normalizedPhoneNumber(_ rawValue: String) -> String {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return raw
        }

        let compact = raw.replacingOccurrences(
            of: #"[^\d+]"#,
            with: "",
            options: .regularExpression
        )

        if compact.hasPrefix("+") {
            return compact
        }

        if compact.hasPrefix("00") {
            return "+\(compact.dropFirst(2))"
        }

        // Local Egypt mobile format (01xxxxxxxxx) -> +20xxxxxxxxxx
        if compact.count == 11, compact.hasPrefix("01") {
            return "+20\(compact.dropFirst())"
        }

        return "+\(compact)"
    }
}
