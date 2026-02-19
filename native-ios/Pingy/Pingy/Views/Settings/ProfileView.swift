import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @ObservedObject var viewModel: MessengerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var bio = ""
    @State private var showOnline = true
    @State private var readReceipts = true
    @State private var avatarItem: PhotosPickerItem?
    @State private var showSavedBadge = false

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                profileHeader
                profileCard
                privacyCard
                securityCard
                blockedUsersCard
                accountCard
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("My Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .onAppear {
            username = viewModel.currentUserSettings?.username ?? ""
            bio = viewModel.currentUserSettings?.bio ?? ""
            showOnline = viewModel.currentUserSettings?.showOnlineStatus ?? true
            readReceipts = viewModel.currentUserSettings?.readReceiptsEnabled ?? true
        }
        .onChange(of: avatarItem) { newItem in
            guard let newItem else { return }
            Task {
                let contentType = newItem.supportedContentTypes.first
                let extensionPart = contentType?.preferredFilenameExtension ?? "jpg"
                let mimeType = contentType?.preferredMIMEType ?? "image/jpeg"

                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let success = await viewModel.uploadAvatar(
                        data,
                        fileName: "avatar-\(UUID().uuidString).\(extensionPart)",
                        mimeType: mimeType
                    )
                    if success {
                        showSuccessBadge()
                    }
                }
                avatarItem = nil
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: PingySpacing.md) {
            ZStack {
                AvatarView(
                    url: viewModel.currentUserSettings?.avatarUrl,
                    fallback: viewModel.currentUserSettings?.username ?? "U",
                    size: 92,
                    cornerRadius: 28
                )

                if viewModel.isUploadingAvatar {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 92, height: 92)
                    ProgressView()
                        .tint(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentUserSettings?.username ?? "Pingy user")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                Text(viewModel.currentUserSettings?.phoneNumber ?? "")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            }

            Spacer()

            PhotosPicker(selection: $avatarItem, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(PingyTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Profile")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            labeledTextField("Username", text: $username)

            VStack(alignment: .leading, spacing: 6) {
                Text("Bio")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)

                TextField("Add bio...", text: $bio, axis: .vertical)
                    .lineLimit(3 ... 6)
                    .padding(12)
                    .background(PingyTheme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PingyTheme.border, lineWidth: 1)
                    )
            }

            Button {
                Task {
                    let success = await viewModel.saveProfile(username: username, bio: bio)
                    if success {
                        showSuccessBadge()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSavingProfile {
                        ProgressView().tint(.white)
                    }
                    Text("Save profile")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(PingyTheme.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
            .disabled(viewModel.isSavingProfile)

            if showSavedBadge {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Saved successfully")
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.success)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .pingyCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Privacy")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Toggle("Show online status", isOn: $showOnline)
                .tint(PingyTheme.primary)
            Toggle("Read receipts", isOn: $readReceipts)
                .tint(PingyTheme.primary)

            Button("Save privacy") {
                PingyHaptics.softTap()
                Task { await viewModel.savePrivacy(showOnline: showOnline, readReceipts: readReceipts) }
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
                            .foregroundStyle(PingyTheme.textPrimary)
                        Spacer()
                        Button("Unblock") {
                            Task { await viewModel.unblockUser(blocked.id) }
                        }
                        .buttonStyle(PingyPressableButtonStyle())
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
        .pingyCard()
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Security")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            infoRow(title: "Device ID", value: viewModel.currentUserSettings?.deviceId ?? "This device")
            infoRow(title: "Last login", value: viewModel.currentUserSettings?.lastLoginAt ?? "Unknown")
        }
        .pingyCard()
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Account")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Button {
                Task { await viewModel.logout() }
            } label: {
                Text("Logout")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(PingyTheme.primarySoft)
                    .foregroundStyle(PingyTheme.primaryStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private func labeledTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
            TextField("", text: text)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .padding(12)
                .background(PingyTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PingyTheme.border, lineWidth: 1)
                )
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showSuccessBadge() {
        PingyHaptics.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showSavedBadge = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                showSavedBadge = false
            }
        }
    }
}
