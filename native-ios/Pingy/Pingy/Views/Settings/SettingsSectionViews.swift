import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AccountSettingsSectionView: View {
    @ObservedObject var viewModel: MessengerViewModel

    @State private var showLogoutConfirmation = false
    @State private var showDeleteAccountConfirmation = false

    var body: some View {
        List {
            Section(String(localized: "Account")) {
                NavigationLink {
                    ChangePhoneNumberView(viewModel: viewModel)
                } label: {
                    sectionItem(
                        title: "Change phone number",
                        subtitle: "Secure verification required",
                        icon: "phone.arrow.up.right"
                    )
                }
            }

            Section(String(localized: "Session")) {
                Button {
                    showLogoutConfirmation = true
                } label: {
                    sectionItem(
                        title: "Logout",
                        subtitle: "Sign out from this device",
                        icon: "rectangle.portrait.and.arrow.right"
                    )
                }
                .buttonStyle(.plain)
            }

            Section(String(localized: "Danger zone")) {
                Button(role: .destructive) {
                    showDeleteAccountConfirmation = true
                } label: {
                    sectionItem(
                        title: "Delete account",
                        subtitle: "This permanently removes account data",
                        icon: "trash"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Account"))
        .confirmationDialog(
            String(localized: "Logout from this device?"),
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Logout"), role: .destructive) {
                Task { await viewModel.logout() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            String(localized: "Delete your account permanently?"),
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete account"), role: .destructive) {
                Task { await viewModel.deleteMyAccount() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }

    private func sectionItem(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PingyTheme.primaryStrong)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            }
        }
    }
}

struct NotificationSettingsSectionView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @AppStorage("pingy.v3.notifications.messages") private var messageNotifications = true
    @AppStorage("pingy.v3.notifications.groups") private var groupNotifications = true
    @AppStorage("pingy.v3.notifications.preview") private var previewEnabled = true
    @AppStorage("pingy.v3.notifications.sound") private var selectedNotificationSound = "Default"

    var body: some View {
        List {
            Section(String(localized: "Messages")) {
                Toggle(String(localized: "Message notifications"), isOn: $messageNotifications)
                    .tint(PingyTheme.primary)
                Toggle(String(localized: "Group notifications"), isOn: $groupNotifications)
                    .tint(PingyTheme.primary)
                Toggle(String(localized: "Preview message"), isOn: $previewEnabled)
                    .tint(PingyTheme.primary)
            }

            Section(String(localized: "Sound")) {
                Picker(String(localized: "Notification sound"), selection: $selectedNotificationSound) {
                    Text(String(localized: "Default")).tag("Default")
                    Text(String(localized: "Ripple")).tag("Ripple")
                    Text(String(localized: "Echo")).tag("Echo")
                }
            }

            Section(String(localized: "System access")) {
                if !appEnvironment.pushManager.serverAPNsEnabled {
                    Text(String(localized: "APNs server is not configured. Remote notifications are currently unavailable."))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                } else if let issue = appEnvironment.pushManager.registrationIssue {
                    Text(issue)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }

                Button(String(localized: "Configure iOS notification permission")) {
                    Task { await appEnvironment.pushManager.requestPermission() }
                }
                .foregroundStyle(PingyTheme.primaryStrong)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Notifications"))
    }
}

struct PrivacySecuritySettingsSectionView: View {
    @ObservedObject var viewModel: MessengerViewModel

    @AppStorage("pingy.v3.lastSeenVisibility") private var lastSeenVisibility = "Contacts"
    @AppStorage("pingy.v3.profilePhotoPrivacy") private var profilePhotoPrivacy = "Everyone"
    @AppStorage("pingy.v3.statusPrivacy") private var statusPrivacy = "contacts"

    @State private var showOnlineStatus = true
    @State private var readReceipts = true
    @State private var didInitialize = false
    @State private var privacySaveTask: Task<Void, Never>?

    var body: some View {
        List {
            Section(String(localized: "Visibility")) {
                Picker(String(localized: "Last seen"), selection: $lastSeenVisibility) {
                    Text(String(localized: "Everyone")).tag("Everyone")
                    Text(String(localized: "Contacts")).tag("Contacts")
                    Text(String(localized: "Nobody")).tag("Nobody")
                }

                Toggle(String(localized: "Online status"), isOn: $showOnlineStatus)
                    .tint(PingyTheme.primary)

                Toggle(String(localized: "Read receipts"), isOn: $readReceipts)
                    .tint(PingyTheme.primary)

                Picker(String(localized: "Profile photo privacy"), selection: $profilePhotoPrivacy) {
                    Text(String(localized: "Everyone")).tag("Everyone")
                    Text(String(localized: "Contacts")).tag("Contacts")
                    Text(String(localized: "Nobody")).tag("Nobody")
                }

                Picker(String(localized: "Status privacy"), selection: $statusPrivacy) {
                    Text(String(localized: "My contacts")).tag("contacts")
                    Text(String(localized: "Custom")).tag("custom")
                }
            }

            Section(String(localized: "Security")) {
                NavigationLink {
                    BlockedUsersListView(viewModel: viewModel)
                } label: {
                    HStack {
                        Text(String(localized: "Blocked users"))
                        Spacer()
                        Text("\(viewModel.blockedUsers.count)")
                            .foregroundStyle(PingyTheme.textSecondary)
                    }
                }

                NavigationLink {
                    SettingsView(viewModel: viewModel, mode: .twoStep, showsCloseButton: false)
                } label: {
                    HStack {
                        Text(String(localized: "Two-step verification"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Privacy & Security"))
        .onAppear {
            showOnlineStatus = viewModel.currentUserSettings?.showOnlineStatus ?? true
            readReceipts = viewModel.currentUserSettings?.readReceiptsEnabled ?? true
            statusPrivacy = normalizedStatusPrivacy(statusPrivacy)
            didInitialize = true
        }
        .onChange(of: showOnlineStatus) { _ in
            queuePrivacyAutosave()
        }
        .onChange(of: readReceipts) { _ in
            queuePrivacyAutosave()
        }
        .onDisappear {
            privacySaveTask?.cancel()
        }
    }

    private func normalizedStatusPrivacy(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "custom" {
            return "custom"
        }
        return "contacts"
    }

    private func queuePrivacyAutosave() {
        guard didInitialize else { return }

        var updated = viewModel.currentUserSettings
        updated?.showOnlineStatus = showOnlineStatus
        updated?.readReceiptsEnabled = readReceipts
        viewModel.currentUserSettings = updated

        privacySaveTask?.cancel()
        privacySaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            await viewModel.savePrivacy(showOnline: showOnlineStatus, readReceipts: readReceipts)
        }
    }
}

struct DataStorageSettingsSectionView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject private var networkUsage = NetworkUsageStore.shared

    @AppStorage("pingy.v3.chat.backupEnabled") private var chatBackupEnabled = false
    @AppStorage("pingy.v3.chat.autoDownloadMedia") private var autoDownloadMedia = true

    var body: some View {
        List {
            Section(String(localized: "Storage")) {
                metricsRow(title: "Image cache", value: formatBytes(Int64(URLCache.shared.currentDiskUsage)))
                metricsRow(title: "Memory cache", value: formatBytes(Int64(URLCache.shared.currentMemoryUsage)))
                metricsRow(title: "Conversations", value: "\(messengerViewModel.conversations.count)")
            }

            Section(String(localized: "Network usage")) {
                metricsRow(title: "Uploaded", value: formatBytes(networkUsage.uploadedBytes))
                metricsRow(title: "Downloaded", value: formatBytes(networkUsage.downloadedBytes))
                metricsRow(title: "Total", value: formatBytes(networkUsage.totalBytes))
            }

            Section(String(localized: "Data options")) {
                Toggle(String(localized: "Chat backup"), isOn: $chatBackupEnabled)
                    .tint(PingyTheme.primary)
                Toggle(String(localized: "Auto-download media"), isOn: $autoDownloadMedia)
                    .tint(PingyTheme.primary)
            }

            Section(String(localized: "Actions")) {
                Button(String(localized: "Clear cache")) {
                    URLCache.shared.removeAllCachedResponses()
                }
                .foregroundStyle(PingyTheme.primaryStrong)

                Button(String(localized: "Reset network usage")) {
                    networkUsage.reset()
                }
                .foregroundStyle(PingyTheme.primaryStrong)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Data & Storage"))
    }

    private func metricsRow(title: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .foregroundStyle(PingyTheme.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(PingyTheme.textPrimary)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct AppearanceSettingsSectionView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var themeManager: ThemeManager

    @AppStorage("pingy.v3.chat.fontScale") private var chatFontScale = 1.0
    @AppStorage("pingy.v3.chat.enterToSend") private var enterToSend = true

    @State private var defaultWallpaperURL = ""
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        List {
            themeSection
            chatLayoutSection
            wallpaperSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Appearance"))
        .onAppear {
            defaultWallpaperURL = messengerViewModel.currentUserSettings?.defaultWallpaperUrl ?? ""
        }
        .onChange(of: themeManager.appearanceMode) { _ in
            scheduleChatAutosave(immediate: true)
        }
        .onChange(of: defaultWallpaperURL) { _ in
            scheduleChatAutosave(immediate: false)
        }
        .onChange(of: wallpaperItem) { newValue in
            guard let newValue else { return }
            Task {
                let contentType = newValue.supportedContentTypes.first
                let extensionPart = contentType?.preferredFilenameExtension ?? "jpg"
                let mimeType = contentType?.preferredMIMEType ?? "image/jpeg"

                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await messengerViewModel.uploadDefaultWallpaper(
                        data,
                        fileName: "default-wallpaper-\(UUID().uuidString).\(extensionPart)",
                        mimeType: mimeType
                    )
                }

                wallpaperItem = nil
            }
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }

    private var themeSection: some View {
        Section(String(localized: "Theme")) {
            Picker(String(localized: "Appearance"), selection: $themeManager.appearanceMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(NSLocalizedString(mode.displayName, comment: "")).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var chatLayoutSection: some View {
        Section(String(localized: "Chat layout")) {
            Toggle(String(localized: "Enter to send"), isOn: $enterToSend)
                .tint(PingyTheme.primary)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Font size"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
                Slider(value: $chatFontScale, in: 0.85 ... 1.25, step: 0.05)
                    .tint(PingyTheme.primary)
            }
            .padding(.vertical, 4)
        }
    }

    private var wallpaperSection: some View {
        Section {
            TextField(String(localized: "Default wallpaper URL (optional)"), text: $defaultWallpaperURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    scheduleChatAutosave(immediate: true)
                }

            PhotosPicker(selection: $wallpaperItem, matching: .images) {
                Label(String(localized: "Upload default wallpaper"), systemImage: "photo")
                    .foregroundStyle(PingyTheme.primaryStrong)
            }
            .buttonStyle(PingyPressableButtonStyle())
        } header: {
            Text(String(localized: "Wallpaper"))
        } footer: {
            Text(String(localized: "Changes in this section are saved automatically."))
        }
    }

    private func scheduleChatAutosave(immediate: Bool) {
        saveTask?.cancel()
        let trimmed = defaultWallpaperURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmed.isEmpty ? nil : trimmed

        saveTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            if Task.isCancelled { return }
            await messengerViewModel.saveChat(
                themeMode: themeManager.appearanceMode,
                defaultWallpaperURL: payload
            )
        }
    }
}

struct AdvancedSettingsSectionView: View {
    @AppStorage("pingy.v3.language") private var appLanguage = "System"

    var body: some View {
        List {
            Section(String(localized: "General")) {
                NavigationLink {
                    LanguageSelectionView()
                } label: {
                    HStack {
                        Image(systemName: "globe")
                            .frame(width: 24)
                            .foregroundStyle(PingyTheme.primaryStrong)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "App language"))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(PingyTheme.textPrimary)
                            Text(localizedLanguageName(appLanguage))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(PingyTheme.textSecondary)
                        }
                    }
                }

                Button(String(localized: "Open iOS app settings")) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .foregroundStyle(PingyTheme.primaryStrong)
            }

            Section(String(localized: "About")) {
                infoRow(title: "Version", value: appVersionString)
                infoRow(title: "Build", value: appBuildString)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Advanced"))
    }

    private var appVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var appBuildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
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
}
