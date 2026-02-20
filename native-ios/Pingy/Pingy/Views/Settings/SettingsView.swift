import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @ObservedObject var viewModel: MessengerViewModel
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var defaultWallpaperURL = ""
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var appearanceMode: ThemeMode = .auto
    @State private var showDeleteAccountConfirmation = false
    @State private var totpStatus: TotpStatusResponse?
    @State private var totpSetup: TotpSetupStartResponse?
    @State private var totpVerifyCode = ""
    @State private var totpDisableCode = ""
    @State private var totpDisableRecoveryCode = ""
    @State private var recoveryCodes: [String] = []
    @State private var totpInfoMessage: String?
    @State private var totpErrorMessage: String?
    @State private var isTotpBusy = false

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                chatCard
                blockedUsersCard
                notificationsCard
                twoStepCard
                accountCard
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .onAppear {
            defaultWallpaperURL = viewModel.currentUserSettings?.defaultWallpaperUrl ?? ""
            appearanceMode = appEnvironment.themeManager.appearanceMode
            Task { await reloadTotpStatus() }
        }
        .onChange(of: wallpaperItem) { newValue in
            guard let newValue else { return }
            Task {
                let contentType = newValue.supportedContentTypes.first
                let extensionPart = contentType?.preferredFilenameExtension ?? "jpg"
                let mimeType = contentType?.preferredMIMEType ?? "image/jpeg"

                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await viewModel.uploadDefaultWallpaper(
                        data,
                        fileName: "default-wallpaper-\(UUID().uuidString).\(extensionPart)",
                        mimeType: mimeType
                    )
                }
                wallpaperItem = nil
            }
        }
        .confirmationDialog(
            "Delete your account permanently?",
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await viewModel.deleteMyAccount() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var chatCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Chat")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)

                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceMode) { newValue in
                    appEnvironment.themeManager.appearanceMode = newValue
                }
            }

            TextField("Default wallpaper URL (optional)", text: $defaultWallpaperURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(PingyTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PingyTheme.border, lineWidth: 1)
                )

            PhotosPicker(selection: $wallpaperItem, matching: .images) {
                Label("Upload default wallpaper", systemImage: "photo")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.primaryStrong)
            }
            .buttonStyle(PingyPressableButtonStyle())

            Button("Save chat settings") {
                Task {
                    let normalized = defaultWallpaperURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    await viewModel.saveChat(
                        themeMode: appearanceMode,
                        defaultWallpaperURL: normalized.isEmpty ? nil : normalized
                    )
                }
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .buttonStyle(PingyPressableButtonStyle())
            .foregroundStyle(PingyTheme.primaryStrong)
        }
        .pingyCard()
    }

    private var blockedUsersCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Blocked users")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            if viewModel.blockedUsers.isEmpty {
                Text("No blocked users.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            } else {
                ForEach(viewModel.blockedUsers) { blocked in
                    HStack {
                        AvatarView(url: blocked.avatarUrl, fallback: blocked.username, size: 40, cornerRadius: 12)
                        Text(blocked.username)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                        Button("Unblock") {
                            Task { await viewModel.unblockUser(blocked.id) }
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .buttonStyle(PingyPressableButtonStyle())
                    }
                }
            }
        }
        .pingyCard()
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Notifications")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Text("Enable APNs notifications to get chat updates when the app is closed.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)

            Button("Enable notifications") {
                Task {
                    await appEnvironment.pushManager.requestPermission()
                }
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .buttonStyle(PingyPressableButtonStyle())
            .foregroundStyle(PingyTheme.primaryStrong)
        }
        .pingyCard()
    }

    private var twoStepCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Two-step verification")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            if let status = totpStatus {
                Text(status.enabled ? "Authenticator is active." : "Authenticator is not active yet.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)

                Text("Recovery codes left: \(status.recoveryCodesAvailable)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            } else {
                Text("Checking authenticator status...")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            }

            if let error = totpErrorMessage {
                statusChip(text: error, color: PingyTheme.danger.opacity(0.12), textColor: PingyTheme.danger)
            }

            if let info = totpInfoMessage {
                statusChip(text: info, color: PingyTheme.success.opacity(0.12), textColor: PingyTheme.success)
            }

            if let setup = totpSetup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1) Add this key to your Authenticator app")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                    Text(setup.secret)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(PingyTheme.primaryStrong)

                    HStack(spacing: 10) {
                        Button("Open Authenticator") {
                            if let url = URL(string: setup.otpAuthUrl) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(PingyPressableButtonStyle())

                        Button("Copy key") {
                            UIPasteboard.general.string = setup.secret
                        }
                        .buttonStyle(PingyPressableButtonStyle())
                    }

                    Text("2) Enter the 6-digit code from Authenticator")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                    TextField("123456", text: $totpVerifyCode)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(PingyTheme.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(PingyTheme.border, lineWidth: 1)
                        )

                    Button {
                        Task { await confirmTotpSetup() }
                    } label: {
                        Text("Activate authenticator")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                    .disabled(isTotpBusy)
                }
                .padding(12)
                .background(PingyTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if !recoveryCodes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save these recovery codes now")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.danger)

                    ForEach(recoveryCodes, id: \.self) { code in
                        Text(code)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(PingyTheme.textPrimary)
                    }
                }
                .padding(12)
                .background(PingyTheme.warning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    Task { await beginTotpSetup() }
                } label: {
                    Text("Set up authenticator")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .buttonStyle(PingyPressableButtonStyle())
                .disabled(isTotpBusy)

                Button {
                    Task { await reloadTotpStatus() }
                } label: {
                    Text("Refresh")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .buttonStyle(PingyPressableButtonStyle())
                .disabled(isTotpBusy)
            }

            if totpStatus?.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Disable authenticator")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)

                    TextField("Authenticator code", text: $totpDisableCode)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(PingyTheme.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(PingyTheme.border, lineWidth: 1)
                        )

                    TextField("Or recovery code", text: $totpDisableRecoveryCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(PingyTheme.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(PingyTheme.border, lineWidth: 1)
                        )

                    Button("Disable authenticator", role: .destructive) {
                        Task { await disableTotp() }
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                    .disabled(isTotpBusy)
                }
            }
        }
        .pingyCard()
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Account")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Button("Logout") {
                Task {
                    await viewModel.logout()
                }
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(PingyTheme.primaryStrong)
            .buttonStyle(PingyPressableButtonStyle())

            Button("Delete account", role: .destructive) {
                showDeleteAccountConfirmation = true
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private func statusChip(text: String, color: Color, textColor: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func reloadTotpStatus() async {
        isTotpBusy = true
        defer { isTotpBusy = false }

        do {
            totpStatus = try await appEnvironment.authService.getTotpStatus()
            totpErrorMessage = nil
        } catch {
            totpErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func beginTotpSetup() async {
        isTotpBusy = true
        defer { isTotpBusy = false }

        do {
            let setup = try await appEnvironment.authService.startTotpSetup()
            totpSetup = setup
            totpVerifyCode = ""
            recoveryCodes = []
            totpErrorMessage = nil
            totpInfoMessage = "Authenticator secret generated. Add it then verify code."
            await reloadTotpStatus()
        } catch {
            totpErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func confirmTotpSetup() async {
        let code = totpVerifyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            totpErrorMessage = "Enter authenticator code first."
            return
        }

        isTotpBusy = true
        defer { isTotpBusy = false }

        do {
            let result = try await appEnvironment.authService.verifyTotpSetup(code: code)
            recoveryCodes = result.recoveryCodes
            totpInfoMessage = result.message
            totpErrorMessage = nil
            totpSetup = nil
            totpVerifyCode = ""
            await reloadTotpStatus()
        } catch {
            totpErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func disableTotp() async {
        let code = totpDisableCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let recovery = totpDisableRecoveryCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if code.isEmpty && recovery.isEmpty {
            totpErrorMessage = "Enter authenticator code or recovery code."
            return
        }
        if !code.isEmpty && !recovery.isEmpty {
            totpErrorMessage = "Use authenticator code or recovery code, not both."
            return
        }

        isTotpBusy = true
        defer { isTotpBusy = false }

        do {
            let message = try await appEnvironment.authService.disableTotp(
                code: code.isEmpty ? nil : code,
                recoveryCode: recovery.isEmpty ? nil : recovery
            )
            totpInfoMessage = message
            totpErrorMessage = nil
            totpDisableCode = ""
            totpDisableRecoveryCode = ""
            totpSetup = nil
            recoveryCodes = []
            await reloadTotpStatus()
        } catch {
            totpErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
