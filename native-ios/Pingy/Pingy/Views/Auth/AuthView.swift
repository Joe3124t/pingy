import SwiftUI

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.90, green: 0.97, blue: 0.99), Color(red: 0.84, green: 0.94, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                header
                form
            }
            .padding(20)
            .frame(maxWidth: 460)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("PINGY")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.00, green: 0.38, blue: 0.48))
            }

            Text(title)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
    }

    private var form: some View {
        VStack(spacing: 14) {
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
                statusView(text: error, color: .red.opacity(0.14), textColor: .red)
            }

            if let info = viewModel.infoMessage {
                statusView(text: info, color: .green.opacity(0.14), textColor: .green)
            }

            Button {
                Task { await viewModel.submit() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(primaryButtonTitle)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(red: 0.06, green: 0.47, blue: 0.60))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(viewModel.isLoading)

            Button {
                withAnimation(.spring) {
                    viewModel.switchMode(viewModel.mode == .forgotPassword ? .login : .forgotPassword)
                }
            } label: {
                Text(viewModel.mode == .forgotPassword || viewModel.mode == .confirmReset ? "Back to login" : "Forgot password?")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 24, y: 16)
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            pickerButton("Login", mode: .login)
            pickerButton("Register", mode: .register)
        }
        .padding(4)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(viewModel.mode == .forgotPassword || viewModel.mode == .confirmReset ? 0.3 : 1)
        .allowsHitTesting(!(viewModel.mode == .forgotPassword || viewModel.mode == .confirmReset))
    }

    private func pickerButton(_ title: String, mode: AuthViewModel.Mode) -> some View {
        Button {
            withAnimation(.spring) {
                viewModel.switchMode(mode)
            }
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(viewModel.mode == mode ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(viewModel.mode == mode ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func inputField(title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
            TextField("", text: text)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func secureInputField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
            SecureField("", text: text)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func statusView(text: String, color: Color, textColor: Color) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            return "Native secure messaging with end-to-end encryption."
        case .register:
            return "Set up your secure Pingy profile."
        case .forgotPassword:
            return "We will send a 6-digit code to your email."
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
