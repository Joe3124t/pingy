import SwiftUI

struct ChangePhoneNumberView: View {
    @ObservedObject var viewModel: MessengerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newPhoneNumber = ""
    @State private var currentPassword = ""
    @State private var totpCode = ""
    @State private var recoveryCode = ""
    @State private var isSaving = false
    @State private var successMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Current number"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                    Text(viewModel.currentUserSettings?.phoneNumber ?? String(localized: "Unknown"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                }
                .padding(.vertical, 4)
            } header: {
                Text(String(localized: "Account"))
            }

            Section {
                TextField(String(localized: "New phone number (+201...)"), text: $newPhoneNumber)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.phonePad)

                SecureField(String(localized: "Current password"), text: $currentPassword)

                if viewModel.currentUserSettings?.totpEnabled == true {
                    TextField(String(localized: "Authenticator code (optional)"), text: $totpCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numberPad)

                    TextField(String(localized: "Recovery code (optional)"), text: $recoveryCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            } header: {
                Text(String(localized: "Verification"))
            } footer: {
                if viewModel.currentUserSettings?.totpEnabled == true {
                    Text(String(localized: "If your account uses authenticator, enter code or recovery code."))
                } else {
                    Text(String(localized: "For security, your current password is required."))
                }
            }

            Section {
                Button {
                    Task { await submitChange() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(String(localized: "Change phone number"))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving)
            }

            if let successMessage {
                Section {
                    Text(successMessage)
                        .foregroundStyle(PingyTheme.success)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Change phone number"))
    }

    private func submitChange() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let success = await viewModel.changePhoneNumber(
            newPhoneNumber: newPhoneNumber,
            currentPassword: currentPassword,
            totpCode: totpCode.isEmpty ? nil : totpCode,
            recoveryCode: recoveryCode.isEmpty ? nil : recoveryCode
        )

        guard success else { return }

        successMessage = String(localized: "Phone number updated successfully.")
        try? await Task.sleep(nanoseconds: 900_000_000)
        dismiss()
    }
}
