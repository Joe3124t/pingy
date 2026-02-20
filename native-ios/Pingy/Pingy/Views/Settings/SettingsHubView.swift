import SwiftUI

struct SettingsHubView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var themeManager: ThemeManager
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @ObservedObject private var networkUsage = NetworkUsageStore.shared

    @AppStorage("pingy.v3.language") private var appLanguage = "System"
    @AppStorage("pingy.v3.lastSeenVisibility") private var lastSeenVisibility = "Contacts"
    @AppStorage("pingy.v3.profilePhotoPrivacy") private var profilePhotoPrivacy = "Everyone"
    @AppStorage("pingy.v3.statusPrivacy") private var statusPrivacy = "Contacts"
    @AppStorage("pingy.v3.chat.backupEnabled") private var chatBackupEnabled = false
    @AppStorage("pingy.v3.chat.autoDownloadMedia") private var autoDownloadMedia = true
    @AppStorage("pingy.v3.chat.fontScale") private var chatFontScale = 1.0
    @AppStorage("pingy.v3.chat.enterToSend") private var enterToSend = true
    @AppStorage("pingy.v3.notifications.messages") private var messageNotifications = true
    @AppStorage("pingy.v3.notifications.groups") private var groupNotifications = true
    @AppStorage("pingy.v3.notifications.preview") private var previewEnabled = true
    @AppStorage("pingy.v3.notifications.sound") private var selectedNotificationSound = "Default"

    @State private var showDeleteAccountConfirmation = false
    @State private var showPrivacySaved = false

    var body: some View {
        List {
            profileSection
            accountSection
            privacySection
            chatsSection
            notificationsSection
            storageSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete your account permanently?",
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await messengerViewModel.deleteMyAccount() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileView(viewModel: messengerViewModel)
            } label: {
                HStack(spacing: PingySpacing.md) {
                    AvatarView(
                        url: messengerViewModel.currentUserSettings?.avatarUrl,
                        fallback: messengerViewModel.currentUserSettings?.username ?? "U",
                        size: 56,
                        cornerRadius: 28
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(messengerViewModel.currentUserSettings?.username ?? "Pingy User")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(PingyTheme.textPrimary)

                        Text(messengerViewModel.currentUserSettings?.bio?.isEmpty == false ? messengerViewModel.currentUserSettings?.bio ?? "" : "Tap to open profile")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PingyTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Profile")
        }
    }

    private var accountSection: some View {
        Section("Account") {
            NavigationLink {
                ChangePhoneNumberView(viewModel: messengerViewModel)
            } label: {
                settingsLabel(
                    title: "Change phone number",
                    subtitle: "Secure verification required",
                    icon: "phone.arrow.up.right"
                )
            }

            NavigationLink {
                SettingsView(viewModel: messengerViewModel, mode: .twoStep, showsCloseButton: false)
            } label: {
                settingsLabel(
                    title: "Security",
                    subtitle: "Two-step verification & recovery",
                    icon: "checkmark.shield"
                )
            }

            NavigationLink {
                LanguageSelectionView()
            } label: {
                settingsLabel(
                    title: "App language",
                    subtitle: localizedLanguageName(appLanguage),
                    icon: "globe"
                )
            }

            Button {
                Task { await messengerViewModel.logout() }
            } label: {
                settingsLabel(
                    title: "Logout",
                    subtitle: "Sign out from this device",
                    icon: "rectangle.portrait.and.arrow.right"
                )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                showDeleteAccountConfirmation = true
            } label: {
                settingsLabel(
                    title: "Delete account",
                    subtitle: "Remove account and data",
                    icon: "trash"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Picker("Last seen", selection: $lastSeenVisibility) {
                Text("Everyone").tag("Everyone")
                Text("Contacts").tag("Contacts")
                Text("Nobody").tag("Nobody")
            }

            Toggle("Online status", isOn: Binding(
                get: { messengerViewModel.currentUserSettings?.showOnlineStatus ?? true },
                set: { newValue in
                    var settings = messengerViewModel.currentUserSettings
                    settings?.showOnlineStatus = newValue
                    messengerViewModel.currentUserSettings = settings
                }
            ))
            .tint(PingyTheme.primary)

            Toggle("Read receipts", isOn: Binding(
                get: { messengerViewModel.currentUserSettings?.readReceiptsEnabled ?? true },
                set: { newValue in
                    var settings = messengerViewModel.currentUserSettings
                    settings?.readReceiptsEnabled = newValue
                    messengerViewModel.currentUserSettings = settings
                }
            ))
            .tint(PingyTheme.primary)

            Picker("Profile photo privacy", selection: $profilePhotoPrivacy) {
                Text("Everyone").tag("Everyone")
                Text("Contacts").tag("Contacts")
                Text("Nobody").tag("Nobody")
            }

            Picker("Status privacy", selection: $statusPrivacy) {
                Text("My contacts").tag("Contacts")
                Text("Custom").tag("Custom")
            }

            NavigationLink {
                BlockedUsersListView(viewModel: messengerViewModel)
            } label: {
                HStack {
                    Text("Blocked users")
                    Spacer()
                    Text("\(messengerViewModel.blockedUsers.count)")
                        .foregroundStyle(PingyTheme.textSecondary)
                }
            }

            Button(showPrivacySaved ? "Privacy saved" : "Save privacy settings") {
                Task {
                    await messengerViewModel.savePrivacy(
                        showOnline: messengerViewModel.currentUserSettings?.showOnlineStatus ?? true,
                        readReceipts: messengerViewModel.currentUserSettings?.readReceiptsEnabled ?? true
                    )
                    PingyHaptics.softTap()
                    withAnimation(.easeOut(duration: 0.2)) {
                        showPrivacySaved = true
                    }
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    withAnimation(.easeOut(duration: 0.2)) {
                        showPrivacySaved = false
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(PingyTheme.primaryStrong)
        }
    }

    private var chatsSection: some View {
        Section("Chats") {
            Picker("Theme", selection: $themeManager.appearanceMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Chat backup", isOn: $chatBackupEnabled)
                .tint(PingyTheme.primary)

            Toggle("Auto-download media", isOn: $autoDownloadMedia)
                .tint(PingyTheme.primary)

            Toggle("Enter to send", isOn: $enterToSend)
                .tint(PingyTheme.primary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Font size")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
                Slider(value: $chatFontScale, in: 0.85 ... 1.25, step: 0.05)
                    .tint(PingyTheme.primary)
            }

            NavigationLink {
                SettingsView(viewModel: messengerViewModel, mode: .chat, showsCloseButton: false)
            } label: {
                settingsLabel(
                    title: "Wallpaper & advanced chat settings",
                    subtitle: "Default and per-chat customization",
                    icon: "paintbrush.pointed"
                )
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Message notifications", isOn: $messageNotifications)
                .tint(PingyTheme.primary)
            Toggle("Group notifications", isOn: $groupNotifications)
                .tint(PingyTheme.primary)
            Toggle("Preview message", isOn: $previewEnabled)
                .tint(PingyTheme.primary)

            Picker("Sound", selection: $selectedNotificationSound) {
                Text("Default").tag("Default")
                Text("Ripple").tag("Ripple")
                Text("Echo").tag("Echo")
            }

            Button("Configure iOS notification permission") {
                Task { await appEnvironment.pushManager.requestPermission() }
            }
            .foregroundStyle(PingyTheme.primaryStrong)
        }
    }

    private var storageSection: some View {
        Section("Storage & Data") {
            metricsRow(title: "Image cache", value: formatBytes(Int64(URLCache.shared.currentDiskUsage)))
            metricsRow(title: "Memory cache", value: formatBytes(Int64(URLCache.shared.currentMemoryUsage)))
            metricsRow(title: "Uploaded", value: formatBytes(networkUsage.uploadedBytes))
            metricsRow(title: "Downloaded", value: formatBytes(networkUsage.downloadedBytes))
            metricsRow(title: "Total network usage", value: formatBytes(networkUsage.totalBytes))
            metricsRow(title: "Conversations", value: "\(messengerViewModel.conversations.count)")

            Button("Clear cache") {
                URLCache.shared.removeAllCachedResponses()
            }

            Button("Reset network usage") {
                networkUsage.reset()
            }
            .foregroundStyle(PingyTheme.primaryStrong)
        }
    }

    private func settingsLabel(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PingyTheme.primaryStrong)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            }
        }
    }

    private func metricsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(PingyTheme.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(PingyTheme.textPrimary)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
    }

    private func localizedLanguageName(_ value: String) -> String {
        switch value {
        case "Arabic":
            return String(localized: "Arabic")
        case "English":
            return String(localized: "English")
        default:
            return String(localized: "System")
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
