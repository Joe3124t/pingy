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
            .frame(maxWidth: 480)
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
                .font(.system(size: 40, weight: .bold, design: .rounded))
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
            modePicker

            if viewModel.mode == .register {
                inputField(title: "Username", text: $viewModel.username, keyboard: .default)
            }

            inputField(title: "Email", text: $viewModel.email, keyboard: .emailAddress)

            if viewModel.mode == .confirmReset {
                inputField(title: "Reset code", text: $viewModel.resetCode, keyboard: .numberPad)
                secureInputField(title: "New password", text: $viewModel.newPassword)
                secureInputField(title: "Confirm password", text: $viewModel.confirmPassword)
            } else if viewModel.mode != .forgotPassword {
                secureInputField(title: "Password", text: $viewModel.password)
            }

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
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(PingyTheme.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: PingyRadius.input, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
            .disabled(viewModel.isLoading)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.switchMode(viewModel.mode == .forgotPassword ? .login : .forgotPassword)
                }
            } label: {
                Text(viewModel.mode == .forgotPassword || viewModel.mode == .confirmReset ? "Back to login" : "Forgot password?")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
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
        .pingyCard()
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            pickerButton("Login", mode: .login)
            pickerButton("Register", mode: .register)
        }
        .padding(4)
        .background(PingyTheme.primarySoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(viewModel.mode == .forgotPassword || viewModel.mode == .confirmReset ? 0.35 : 1)
        .allowsHitTesting(!(viewModel.mode == .forgotPassword || viewModel.mode == .confirmReset))
    }

    private func pickerButton(_ title: String, mode: AuthViewModel.Mode) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.switchMode(mode)
            }
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(viewModel.mode == mode ? PingyTheme.textPrimary : PingyTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(viewModel.mode == mode ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PingyPressableButtonStyle())
    }

    private func inputField(title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
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
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var title: String {
        switch viewModel.mode {
        case .login:
            return "Welcome back"
        case .register:
            return "Create account"
        case .forgotPassword:
            return "Forgot password"
        case .confirmReset:
            return "Reset password"
        }
    }

    private var subtitle: String {
        switch viewModel.mode {
        case .login:
            return "Secure native messaging with end-to-end encryption."
        case .register:
            return "Create your private Pingy identity."
        case .forgotPassword:
            return "We'll send a 6-digit reset code to your email."
        case .confirmReset:
            return "Enter your code and set a new password."
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.mode {
        case .login:
            return "Login"
        case .register:
            return "Register"
        case .forgotPassword:
            return "Send reset code"
        case .confirmReset:
            return "Update password"
        }
    }
}
