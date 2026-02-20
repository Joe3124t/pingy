import SwiftUI

struct SettingsHubView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var themeManager: ThemeManager
    @EnvironmentObject private var appEnvironment: AppEnvironment

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
    @AppStorage("pingy.v3.notifications.inAppSounds") private var inAppSounds = true
    @AppStorage("pingy.v3.notifications.badges") private var badgeEnabled = true
    @AppStorage("pingy.v3.notifications.preview") private var previewEnabled = true
    @AppStorage("pingy.v3.calls.customSound") private var customCallSound = "Default"

    @State private var showDeleteAccountConfirmation = false
    @State private var showPhoneChangeInfo = false
    @State private var showPrivacySaved = false

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                profileSection
                accountSection
                privacySection
                chatsSection
                notificationsSection
                storageSection
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .alert("Update", isPresented: $showPhoneChangeInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Phone number change flow will be available in an upcoming secure update.")
        }
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
        NavigationLink {
            ProfileView(viewModel: messengerViewModel)
        } label: {
            HStack(spacing: PingySpacing.md) {
                AvatarView(
                    url: messengerViewModel.currentUserSettings?.avatarUrl,
                    fallback: messengerViewModel.currentUserSettings?.username ?? "U",
                    size: 72,
                    cornerRadius: 36
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(messengerViewModel.currentUserSettings?.username ?? "Pingy User")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                    Text(messengerViewModel.currentUserSettings?.phoneNumber ?? "")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                    Text(messengerViewModel.currentUserSettings?.bio?.isEmpty == false ? messengerViewModel.currentUserSettings?.bio ?? "" : "Tap to edit profile")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PingyTheme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pingyCard()
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            sectionTitle("Account")

            settingsRow(icon: "phone.arrow.up.right", title: "Change phone number", subtitle: "Secure migration") {
                showPhoneChangeInfo = true
            }

            NavigationLink {
                LanguageSelectionView()
            } label: {
                settingsRowLabel(
                    icon: "globe",
                    title: "App language",
                    subtitle: localizedLanguageName(appLanguage)
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                SettingsView(viewModel: messengerViewModel, mode: .twoStep, showsCloseButton: false)
            } label: {
                settingsRowLabel(icon: "checkmark.shield", title: "Two-step verification", subtitle: "Authenticator & recovery codes")
            }
            .buttonStyle(.plain)

            Button {
                Task { await messengerViewModel.logout() }
            } label: {
                settingsRowLabel(icon: "rectangle.portrait.and.arrow.right", title: "Logout", subtitle: "Sign out from this device")
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                showDeleteAccountConfirmation = true
            } label: {
                settingsRowLabel(icon: "trash", title: "Delete account", subtitle: "Remove account and data")
            }
            .buttonStyle(.plain)
        }
        .pingyCard()
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            sectionTitle("Privacy")

            Picker("Last seen", selection: $lastSeenVisibility) {
                Text("Everyone").tag("Everyone")
                Text("Contacts").tag("Contacts")
                Text("Nobody").tag("Nobody")
            }
            .pickerStyle(.segmented)

            Toggle("Show online status", isOn: Binding(
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
            .pickerStyle(.menu)

            Picker("Status privacy", selection: $statusPrivacy) {
                Text("My contacts").tag("Contacts")
                Text("Custom").tag("Custom")
            }
            .pickerStyle(.menu)

            Button {
                PingyHaptics.softTap()
                showPrivacySaved = true
                Task {
                    await messengerViewModel.savePrivacy(
                        showOnline: messengerViewModel.currentUserSettings?.showOnlineStatus ?? true,
                        readReceipts: messengerViewModel.currentUserSettings?.readReceiptsEnabled ?? true
                    )
                }
            } label: {
                Text(showPrivacySaved ? "Saved" : "Save privacy settings")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(PingyTheme.primarySoft)
                    .foregroundStyle(PingyTheme.primaryStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private var chatsSection: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            sectionTitle("Chats")

            Picker("Appearance", selection: $themeManager.appearanceMode) {
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Font size")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
                Slider(value: $chatFontScale, in: 0.85 ... 1.25, step: 0.05)
                    .tint(PingyTheme.primary)
            }

            NavigationLink {
                SettingsView(viewModel: messengerViewModel, mode: .chat, showsCloseButton: false)
            } label: {
                settingsRowLabel(icon: "paintbrush.pointed", title: "Wallpaper & advanced chat settings", subtitle: "Default and per-chat customization")
            }
            .buttonStyle(.plain)
        }
        .pingyCard()
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            sectionTitle("Notifications")

            Toggle("Message notifications", isOn: $messageNotifications)
                .tint(PingyTheme.primary)
            Toggle("Group notifications", isOn: $groupNotifications)
                .tint(PingyTheme.primary)
            Toggle("In-app sounds", isOn: $inAppSounds)
                .tint(PingyTheme.primary)
            Toggle("Badge count", isOn: $badgeEnabled)
                .tint(PingyTheme.primary)
            Toggle("Preview message", isOn: $previewEnabled)
                .tint(PingyTheme.primary)

            Picker("Call sound", selection: $customCallSound) {
                Text("Default").tag("Default")
                Text("Ripple").tag("Ripple")
                Text("Echo").tag("Echo")
            }
            .pickerStyle(.menu)

            Button {
                Task { await appEnvironment.pushManager.requestPermission() }
            } label: {
                Text("Configure iOS notification permission")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(PingyTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            sectionTitle("Storage & Data")

            settingsMetricRow(title: "Image cache", value: formatBytes(URLCache.shared.currentDiskUsage))
            settingsMetricRow(title: "Memory cache", value: formatBytes(URLCache.shared.currentMemoryUsage))
            settingsMetricRow(title: "Blocked users", value: "\(messengerViewModel.blockedUsers.count)")
            settingsMetricRow(title: "Conversations", value: "\(messengerViewModel.conversations.count)")

            Button {
                URLCache.shared.removeAllCachedResponses()
            } label: {
                Text("Clear cache")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(PingyTheme.surfaceElevated)
                    .foregroundStyle(PingyTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private func settingsRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            settingsRowLabel(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(PingyPressableButtonStyle())
    }

    private func settingsRowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PingyTheme.primaryStrong)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(PingyTheme.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private func settingsMetricRow(title: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(PingyTheme.textPrimary)
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

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
