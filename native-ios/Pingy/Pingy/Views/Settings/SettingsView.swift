import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: MessengerViewModel
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var defaultWallpaperURL = ""
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var showDeleteAccountConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                chatCard
                blockedUsersCard
                notificationsCard
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

            Text("Theme is locked to Light mode in v1.1 for consistent readability.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)

            TextField("Default wallpaper URL (optional)", text: $defaultWallpaperURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(.white)
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
                        themeMode: .light,
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
}
