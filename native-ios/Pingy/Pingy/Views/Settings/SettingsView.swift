import PhotosUI
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MessengerViewModel
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var themeMode: ThemeMode = .auto
    @State private var defaultWallpaperURL = ""
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var showDeleteAccountConfirmation = false

    var body: some View {
        Form {
            Section("Chat settings") {
                Picker("Theme", selection: $themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }

                TextField("Default wallpaper URL (optional)", text: $defaultWallpaperURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                PhotosPicker(selection: $wallpaperItem, matching: .images) {
                    Label("Upload default wallpaper", systemImage: "photo")
                }

                Button("Save chat settings") {
                    Task {
                        await viewModel.saveChat(
                            themeMode: themeMode,
                            defaultWallpaperURL: defaultWallpaperURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                }
            }

            Section("Blocked users") {
                if viewModel.blockedUsers.isEmpty {
                    Text("No blocked users")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.blockedUsers) { blocked in
                        HStack {
                            AvatarView(url: blocked.avatarUrl, fallback: blocked.username)
                            Text(blocked.username)
                            Spacer()
                            Button("Unblock") {
                                Task {
                                    await viewModel.unblockUser(blocked.id)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Notifications") {
                Text("Enable APNs push notifications to receive new messages when app is closed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Enable notifications") {
                    Task {
                        await appEnvironment.pushManager.requestPermission()
                    }
                }
            }

            Section("Account") {
                Button("Logout") {
                    Task {
                        await viewModel.logout()
                    }
                }
                .foregroundStyle(.orange)

                Button("Delete account", role: .destructive) {
                    showDeleteAccountConfirmation = true
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .onAppear {
            themeMode = viewModel.currentUserSettings?.themeMode ?? .auto
            defaultWallpaperURL = viewModel.currentUserSettings?.defaultWallpaperUrl ?? ""
        }
        .onChange(of: wallpaperItem) { newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await viewModel.uploadDefaultWallpaper(data)
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
                Task {
                    await viewModel.deleteMyAccount()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
