import SwiftUI

struct BlockedUsersListView: View {
    @ObservedObject var viewModel: MessengerViewModel

    var body: some View {
        List {
            if viewModel.blockedUsers.isEmpty {
                Text(String(localized: "No blocked users."))
                    .foregroundStyle(PingyTheme.textSecondary)
            } else {
                ForEach(viewModel.blockedUsers) { blocked in
                    HStack(spacing: PingySpacing.sm) {
                        AvatarView(
                            url: blocked.avatarUrl,
                            fallback: blocked.username,
                            size: 42,
                            cornerRadius: 21
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(blocked.username)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(PingyTheme.textPrimary)
                            if let bio = blocked.bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(bio)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundStyle(PingyTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button(String(localized: "Unblock")) {
                            Task {
                                await viewModel.unblockUser(blocked.id)
                            }
                        }
                        .buttonStyle(PingyPressableButtonStyle())
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Blocked users"))
        .onAppear {
            Task {
                await viewModel.loadSettings(silent: true)
            }
        }
    }
}
