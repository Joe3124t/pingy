import SwiftUI
import UIKit

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            PingyTheme.wallpaperFallback(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: PingySpacing.lg) {
                header
                form
            }
            .padding(PingySpacing.lg)
            .frame(maxWidth: 520)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("PINGY")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.primaryStrong)
            }

            Text(title)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Text(subtitle)
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    private var form: some View {
        VStack(spacing: PingySpacing.sm) {
            fieldSet

            if let error = viewModel.errorMessage {
                statusView(text: error, color: PingyTheme.danger.opacity(0.14), textColor: PingyTheme.danger)
            }

            if let info = viewModel.infoMessage {
                statusView(text: info, color: PingyTheme.success.opacity(0.14), textColor: PingyTheme.success)
            }

            Button {
                PingyHaptics.softTap()
                Task { await viewModel.submit() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(primaryButtonTitle)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(PingyTheme.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
            .disabled(viewModel.isLoading)

            footerButtons
        }
        .pingyCard()
    }

    @ViewBuilder
    private var fieldSet: some View {
        switch viewModel.mode {
        case .phoneEntry:
            inputField(title: "Phone number", text: $viewModel.phoneNumber, keyboard: .phonePad)

        case .signupAuthenticator:
            inputField(title: "Phone number", text: $viewModel.phoneNumber, keyboard: .phonePad, disabled: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Authenticator key")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)

                Text(viewModel.signupSecret)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(PingyTheme.primaryStrong)

                HStack(spacing: 10) {
                    secondaryButton(title: "Open app") {
                        guard let url = URL(string: viewModel.signupOtpAuthUrl) else { return }
                        openURL(url)
                    }

                    secondaryButton(title: "Copy key") {
                        UIPasteboard.general.string = viewModel.signupSecret
                    }
                }
            }

            inputField(title: "Authenticator code", text: $viewModel.signupCode, keyboard: .numberPad)

        case .registerProfile:
            inputField(title: "Phone number", text: $viewModel.phoneNumber, keyboard: .phonePad, disabled: true)
            inputField(title: "Display name", text: $viewModel.displayName, keyboard: .default)
            inputField(title: "Bio", text: $viewModel.bio, keyboard: .default)
            secureInputField(title: "Password", text: $viewModel.password)
            secureInputField(title: "Confirm password", text: $viewModel.confirmPassword)

        case .loginPassword:
            inputField(title: "Phone number", text: $viewModel.phoneNumber, keyboard: .phonePad)
            secureInputField(title: "Password", text: $viewModel.password)

        case .loginTotpVerify:
            if let userHint = viewModel.totpUserHint {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                    Text("\(userHint.username) - \(userHint.phoneMasked)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                }
            }
            inputField(title: "Authenticator code", text: $viewModel.totpCode, keyboard: .numberPad)
            inputField(title: "Recovery code (optional)", text: $viewModel.totpRecoveryCode, keyboard: .default)
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch viewModel.mode {
        case .phoneEntry:
            secondaryButton(title: "I already have a password") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.moveTo(.loginPassword)
                }
            }

        case .signupAuthenticator:
            secondaryButton(title: "Back") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.resetToPhoneEntry()
                }
            }

        case .registerProfile:
            secondaryButton(title: "Back to authenticator") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.moveTo(.signupAuthenticator)
                }
            }

        case .loginPassword:
            secondaryButton(title: "Create new account") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.moveTo(.phoneEntry)
                }
            }

        case .loginTotpVerify:
            secondaryButton(title: "Back to login") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.moveTo(.loginPassword)
                }
            }
        }
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(PingyTheme.surfaceElevated)
                .foregroundStyle(PingyTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous)
                        .stroke(PingyTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(PingyPressableButtonStyle())
    }

    private func inputField(
        title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        disabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            TextField("", text: text)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(PingyTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous)
                        .stroke(PingyTheme.border, lineWidth: 1)
                )
                .disabled(disabled)
                .opacity(disabled ? 0.6 : 1)
        }
    }

    private func secureInputField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            SecureField("", text: text)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(PingyTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous)
                        .stroke(PingyTheme.border, lineWidth: 1)
                )
        }
    }

    private func statusView(text: String, color: Color, textColor: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var title: String {
        switch viewModel.mode {
        case .phoneEntry:
            return "Create account"
        case .signupAuthenticator:
            return "Link authenticator"
        case .registerProfile:
            return "Set profile"
        case .loginPassword:
            return "Login"
        case .loginTotpVerify:
            return "Two-step check"
        }
    }

    private var subtitle: String {
        switch viewModel.mode {
        case .phoneEntry:
            return "Enter phone number to start secure signup."
        case .signupAuthenticator:
            return "Add key in Authenticator then enter code."
        case .registerProfile:
            return "Create password after authenticator verification."
        case .loginPassword:
            return "Enter phone and password."
        case .loginTotpVerify:
            return "Enter your authenticator code to continue."
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.mode {
        case .phoneEntry:
            return "Continue with Authenticator"
        case .signupAuthenticator:
            return "Verify Authenticator code"
        case .registerProfile:
            return "Create account"
        case .loginPassword:
            return "Continue login"
        case .loginTotpVerify:
            return "Verify and login"
        }
    }
}
