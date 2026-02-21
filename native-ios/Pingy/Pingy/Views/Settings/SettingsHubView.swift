import SwiftUI

struct SettingsHubView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ProfileView(viewModel: messengerViewModel)
                } label: {
                    profileHeaderRow
                }
            }

            Section {
                NavigationLink {
                    AccountSettingsSectionView(viewModel: messengerViewModel)
                } label: {
                    SettingsSectionRow(icon: "person.crop.circle", title: "Account")
                }

                NavigationLink {
                    NotificationSettingsSectionView()
                } label: {
                    SettingsSectionRow(icon: "bell.badge", title: "Notifications")
                }

                NavigationLink {
                    PrivacySecuritySettingsSectionView(viewModel: messengerViewModel)
                } label: {
                    SettingsSectionRow(icon: "lock.shield", title: "Privacy & Security")
                }

                NavigationLink {
                    DataStorageSettingsSectionView(messengerViewModel: messengerViewModel)
                } label: {
                    SettingsSectionRow(icon: "internaldrive", title: "Data & Storage")
                }

                NavigationLink {
                    AppearanceSettingsSectionView(
                        messengerViewModel: messengerViewModel,
                        themeManager: themeManager
                    )
                } label: {
                    SettingsSectionRow(icon: "paintbrush", title: "Appearance")
                }

                NavigationLink {
                    AdvancedSettingsSectionView()
                } label: {
                    SettingsSectionRow(icon: "gearshape.2", title: "Advanced")
                }
            }

            Section {
                HStack {
                    Spacer()
                    Text("Pingy v\(appVersionString)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
    }

    private var profileHeaderRow: some View {
        HStack(spacing: PingySpacing.md) {
            AvatarView(
                url: messengerViewModel.currentUserSettings?.avatarUrl,
                fallback: messengerViewModel.currentUserSettings?.username ?? "U",
                size: 58,
                cornerRadius: 29
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(messengerViewModel.currentUserSettings?.username ?? "Pingy User")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)

                Text(messengerViewModel.currentUserSettings?.bio?.isEmpty == false ? messengerViewModel.currentUserSettings?.bio ?? "" : "Open profile")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var appVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.7"
    }
}

private struct SettingsSectionRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PingyTheme.primaryStrong)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}
