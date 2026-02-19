import SwiftUI

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white, PingyTheme.primarySoft],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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

            if let debugCode = viewModel.debugCodeHint, !debugCode.isEmpty {
                statusView(
                    text: "Debug OTP: \(debugCode)",
                    color: PingyTheme.primary.opacity(0.12),
                    textColor: PingyTheme.primaryStrong
                )
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

        case .otpVerify:
            inputField(title: "Phone number", text: $viewModel.phoneNumber, keyboard: .phonePad)
            inputField(title: "OTP code", text: $viewModel.otpCode, keyboard: .numberPad)

        case .registerProfile:
            inputField(title: "Phone number", text: $viewModel.phoneNumber, keyboard: .phonePad, disabled: true)
            inputField(title: "Display name", text: $viewModel.displayName, keyboard: .default)
            inputField(title: "Bio", text: $viewModel.bio, keyboard: .default)
            secureInputField(title: "Password", text: $viewModel.password)
            secureInputField(title: "Confirm password", text: $viewModel.confirmPassword)

        case .loginPassword:
            inputField(title: "Phone number", text: $viewModel.phoneNumber, keyboard: .phonePad)
            secureInputField(title: "Password", text: $viewModel.password)

        case .forgotPasswordRequest:
            inputField(title: "Phone number", text: $viewModel.phoneNumber, keyboard: .phonePad)

        case .forgotPasswordConfirm:
            inputField(title: "Phone number", text: $viewModel.phoneNumber, keyboard: .phonePad)
            inputField(title: "Reset code", text: $viewModel.resetCode, keyboard: .numberPad)
            secureInputField(title: "New password", text: $viewModel.newPassword)
            secureInputField(title: "Confirm password", text: $viewModel.confirmPassword)
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

        case .otpVerify:
            HStack(spacing: 10) {
                secondaryButton(title: "Back") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.resetToPhoneEntry()
                    }
                }
                secondaryButton(title: "Resend code") {
                    Task {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.moveTo(.phoneEntry)
                        }
                        await viewModel.submit()
                    }
                }
            }

        case .registerProfile:
            secondaryButton(title: "Back to OTP") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.moveTo(.otpVerify)
                }
            }

        case .loginPassword:
            HStack(spacing: 10) {
                secondaryButton(title: "Use OTP sign up") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.moveTo(.phoneEntry)
                    }
                }
                secondaryButton(title: "Forgot password") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.moveTo(.forgotPasswordRequest)
                    }
                }
            }

        case .forgotPasswordRequest, .forgotPasswordConfirm:
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
                .background(Color.white)
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
                .background(Color.white)
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
                .background(Color.white)
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
            return "Enter phone"
        case .otpVerify:
            return "Verify OTP"
        case .registerProfile:
            return "Create profile"
        case .loginPassword:
            return "Login"
        case .forgotPasswordRequest:
            return "Reset password"
        case .forgotPasswordConfirm:
            return "Confirm reset"
        }
    }

    private var subtitle: String {
        switch viewModel.mode {
        case .phoneEntry:
            return "Start with your phone number to continue."
        case .otpVerify:
            return "Enter the 6-digit code sent to your phone."
        case .registerProfile:
            return "Set display info and secure password."
        case .loginPassword:
            return "Sign in on this device only."
        case .forgotPasswordRequest:
            return "Request a reset code to your phone."
        case .forgotPasswordConfirm:
            return "Enter code and set a new password."
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.mode {
        case .phoneEntry:
            return "Send OTP"
        case .otpVerify:
            return "Verify code"
        case .registerProfile:
            return "Create account"
        case .loginPassword:
            return "Login"
        case .forgotPasswordRequest:
            return "Send reset code"
        case .forgotPasswordConfirm:
            return "Update password"
        }
    }
}
