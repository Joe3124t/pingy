import SwiftUI

struct ContactsTabView: View {
    @ObservedObject var viewModel: MessengerViewModel
    let onOpenConversation: (Conversation) -> Void
    let onOpenUser: (User) -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: PingySpacing.md) {
                searchField

                if query.isEmpty {
                    contactsList
                } else {
                    searchResultList
                }
            }
            .padding(PingySpacing.md)
            .background(PingyTheme.background.ignoresSafeArea())
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isProfilePresented = true
                    } label: {
                        AvatarView(
                            url: viewModel.currentUserSettings?.avatarUrl,
                            fallback: viewModel.currentUserSettings?.username ?? "U",
                            size: 36,
                            cornerRadius: 18
                        )
                        .overlay(
                            Circle()
                                .stroke(PingyTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }
            }
            .onAppear {
                if viewModel.contactSearchHint == nil {
                    Task { await viewModel.requestContactAccessAndSync() }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: PingySpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PingyTheme.textSecondary)

            TextField("Search contacts", text: $query)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: query) { newValue in
                    viewModel.searchQuery = newValue
                    Task { await viewModel.searchUsers() }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
                    viewModel.contactSearchResults = []
                    viewModel.contactSearchHint = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PingyTheme.textSecondary)
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .padding(.horizontal, PingySpacing.md)
        .padding(.vertical, PingySpacing.sm)
        .pingyCard()
    }

    private var contactsList: some View {
        List {
            ForEach(viewModel.conversations) { conversation in
                Button {
                    onOpenConversation(conversation)
                } label: {
                    HStack(spacing: PingySpacing.sm) {
                        AvatarView(
                            url: conversation.participantAvatarUrl,
                            fallback: viewModel.contactDisplayName(for: conversation),
                            size: 44,
                            cornerRadius: 22
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.contactDisplayName(for: conversation))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(PingyTheme.textPrimary)

                            if let phone = viewModel.contactPhoneNumber(for: conversation.participantId), !phone.isEmpty {
                                Text(phone)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(PingyTheme.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var searchResultList: some View {
        if viewModel.isSyncingContacts {
            ProgressView("Syncing contacts...")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let hint = viewModel.contactSearchHint, viewModel.contactSearchResults.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(hint)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)

                Button("Retry") {
                    Task {
                        await viewModel.requestContactAccessAndSync()
                        viewModel.searchQuery = query
                        await viewModel.searchUsers()
                    }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(PingyTheme.surfaceElevated)
                .foregroundStyle(PingyTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .buttonStyle(PingyPressableButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if viewModel.contactSearchResults.isEmpty {
            Text("No matching contacts found on Pingy.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            List(viewModel.contactSearchResults) { result in
                Button {
                    onOpenUser(result.user)
                } label: {
                    HStack(spacing: PingySpacing.sm) {
                        AvatarView(url: result.user.avatarUrl, fallback: result.contactName, size: 44, cornerRadius: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.contactName)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(PingyTheme.textPrimary)
                            Text(result.user.username)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(PingyTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
