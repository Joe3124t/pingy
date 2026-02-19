import SwiftUI

struct MessengerSplitView: View {
    @ObservedObject var viewModel: MessengerViewModel

    var body: some View {
        NavigationSplitView {
            ConversationSidebarView(viewModel: viewModel)
                .navigationTitle("Pingy")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.isProfilePresented = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
        } detail: {
            if let conversation = viewModel.selectedConversation {
                ChatDetailView(viewModel: viewModel, conversation: conversation)
                    .navigationTitle(conversation.participantUsername)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                viewModel.isChatSettingsPresented = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                            }

                            Button {
                                viewModel.isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            } else {
                noConversationView
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
        }
        .tint(Color(red: 0.04, green: 0.56, blue: 0.70))
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            NavigationStack {
                SettingsView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.isProfilePresented) {
            NavigationStack {
                ProfileView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.isChatSettingsPresented) {
            if let conversation = viewModel.selectedConversation {
                NavigationStack {
                    ChatSettingsView(viewModel: viewModel, conversation: conversation)
                }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.activeError != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.activeError = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    viewModel.activeError = nil
                }
            },
            message: {
                Text(viewModel.activeError ?? "Unknown error")
            }
        )
    }

    private var noConversationView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.06, blue: 0.20), Color(red: 0.01, green: 0.12, blue: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .cyan.opacity(0.35), radius: 14, y: 6)

                Text("No active chat")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Choose a conversation from the sidebar to start encrypted messaging.")
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .padding(30)
            .background(.ultraThinMaterial.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(22)
        }
    }
}

struct ConversationSidebarView: View {
    @ObservedObject var viewModel: MessengerViewModel

    var body: some View {
        VStack(spacing: 14) {
            profileCard
            searchField

            if !viewModel.searchResults.isEmpty {
                List(viewModel.searchResults) { user in
                    Button {
                        Task { await viewModel.openOrCreateConversation(with: user) }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(url: user.avatarUrl, fallback: user.username)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.username)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                Text(user.email ?? "")
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                List(viewModel.conversations) { conversation in
                    Button {
                        Task { await viewModel.selectConversation(conversation.conversationId) }
                    } label: {
                        ConversationRowView(
                            conversation: conversation,
                            isSelected: conversation.conversationId == viewModel.selectedConversationID
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.selectConversation(conversation.conversationId)
                                await viewModel.deleteSelectedConversation(forEveryone: false)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.98, blue: 1.00), Color(red: 0.91, green: 0.96, blue: 0.99)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            AvatarView(url: viewModel.currentUserSettings?.avatarUrl, fallback: viewModel.currentUserSettings?.username ?? "P")
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.currentUserSettings?.username ?? "Pingy User")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Tap profile for privacy & account")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            viewModel.isProfilePresented = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search users", text: $viewModel.searchQuery)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    Task { await viewModel.searchUsers() }
                }
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(url: conversation.participantAvatarUrl, fallback: conversation.participantUsername)
                Circle()
                    .fill(conversation.participantIsOnline ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.participantUsername)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Spacer()
                    if let lastTime = conversation.lastMessageCreatedAt {
                        Text(formatTime(lastTime))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
                Text(lastPreview)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
            }
            if conversation.unreadCount > 0 {
                Text("\(conversation.unreadCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.white.opacity(0.24) : Color.cyan)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(
            isSelected
                ? LinearGradient(
                    colors: [Color(red: 0.03, green: 0.63, blue: 0.82), Color(red: 0.06, green: 0.55, blue: 0.76)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : LinearGradient(
                    colors: [Color.white.opacity(0.86), Color.white.opacity(0.70)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var lastPreview: String {
        if let type = conversation.lastMessageType, type != "text" {
            if let mediaName = conversation.lastMessageMediaName, !mediaName.isEmpty {
                return mediaName
            }
            return type.capitalized
        }
        return conversation.lastMessageBody?.stringValue ?? "No messages yet"
    }

    private func formatTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "" }
        let time = DateFormatter()
        time.timeStyle = .short
        return time.string(from: date)
    }
}
