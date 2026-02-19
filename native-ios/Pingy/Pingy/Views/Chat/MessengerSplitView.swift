import Foundation
import SwiftUI

struct MessengerSplitView: View {
    @ObservedObject var viewModel: MessengerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                MessengerCompactContainer(viewModel: viewModel)
            } else {
                MessengerRegularContainer(viewModel: viewModel)
            }
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .tint(PingyTheme.primary)
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
}

private struct MessengerCompactContainer: View {
    @ObservedObject var viewModel: MessengerViewModel
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ConversationListContent(
                viewModel: viewModel,
                onSelectConversation: { conversation in
                    Task {
                        await viewModel.selectConversation(conversation.conversationId)
                        if path.last != conversation.conversationId {
                            path.append(conversation.conversationId)
                        }
                    }
                },
                onSelectSearchUser: { user in
                    Task {
                        await viewModel.openOrCreateConversation(with: user)
                        if let selectedConversationID = viewModel.selectedConversationID,
                           path.last != selectedConversationID
                        {
                            path.append(selectedConversationID)
                        }
                    }
                }
            )
            .navigationTitle("Pingy")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.isProfilePresented = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .buttonStyle(PingyPressableButtonStyle())

                    Button {
                        viewModel.isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }
            }
            .navigationDestination(for: String.self) { conversationID in
                ConversationDetailHost(
                    viewModel: viewModel,
                    conversationID: conversationID
                )
            }
        }
    }
}

private struct MessengerRegularContainer: View {
    @ObservedObject var viewModel: MessengerViewModel

    var body: some View {
        NavigationSplitView {
            ConversationListContent(
                viewModel: viewModel,
                onSelectConversation: { conversation in
                    Task {
                        await viewModel.selectConversation(conversation.conversationId)
                    }
                },
                onSelectSearchUser: { user in
                    Task {
                        await viewModel.openOrCreateConversation(with: user)
                    }
                }
            )
            .navigationTitle("Pingy")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.isProfilePresented = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .buttonStyle(PingyPressableButtonStyle())

                    Button {
                        viewModel.isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }
            }
        } detail: {
            if let conversation = viewModel.selectedConversation {
                ChatDetailView(viewModel: viewModel, conversation: conversation)
                    .navigationTitle(conversation.participantUsername)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.isChatSettingsPresented = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                            }
                            .buttonStyle(PingyPressableButtonStyle())
                        }
                    }
            } else {
                NoConversationView()
            }
        }
    }
}

private struct ConversationListContent: View {
    @ObservedObject var viewModel: MessengerViewModel
    let onSelectConversation: (Conversation) -> Void
    let onSelectSearchUser: (User) -> Void

    var body: some View {
        VStack(spacing: PingySpacing.md) {
            profileHeader
            searchField

            if !viewModel.searchResults.isEmpty {
                List(viewModel.searchResults) { user in
                    Button {
                        onSelectSearchUser(user)
                    } label: {
                        HStack(spacing: PingySpacing.sm) {
                            AvatarView(url: user.avatarUrl, fallback: user.username)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.username)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(PingyTheme.textPrimary)
                                Text(user.email ?? "")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(PingyTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                List(viewModel.conversations) { conversation in
                    Button {
                        onSelectConversation(conversation)
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
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await viewModel.loadConversations()
                }
            }
        }
        .padding(PingySpacing.md)
        .background(PingyTheme.background.ignoresSafeArea())
    }

    private var profileHeader: some View {
        HStack(spacing: PingySpacing.sm) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Pingy")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.primaryStrong)
                Text("v1.1 - Stability & Native UI Rebuild")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            }

            Spacer()
        }
        .pingyCard()
        .onTapGesture {
            viewModel.isProfilePresented = true
        }
    }

    private var searchField: some View {
        HStack(spacing: PingySpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PingyTheme.textSecondary)

            TextField("Search users", text: $viewModel.searchQuery)
                .font(.system(size: 17, weight: .regular, design: .rounded))
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
                        .foregroundStyle(PingyTheme.textSecondary)
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .padding(.horizontal, PingySpacing.md)
        .padding(.vertical, PingySpacing.sm)
        .pingyCard()
    }
}

private struct ConversationDetailHost: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversationID: String

    var body: some View {
        Group {
            if let conversation = viewModel.conversations.first(where: { $0.conversationId == conversationID }) {
                ChatDetailView(viewModel: viewModel, conversation: conversation)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.isChatSettingsPresented = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                            }
                            .buttonStyle(PingyPressableButtonStyle())
                        }
                    }
            } else if viewModel.isLoadingConversations {
                ProgressView("Loading chat...")
                    .font(.system(.body, design: .rounded))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PingyTheme.background)
            } else {
                NoConversationView(message: "Conversation is unavailable.")
            }
        }
        .task(id: conversationID) {
            await viewModel.selectConversation(conversationID)
        }
    }
}

private struct NoConversationView: View {
    var message: String = "Select a chat from the sidebar to start messaging."

    var body: some View {
        VStack(spacing: PingySpacing.lg) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("No active chat")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Text(message)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PingyTheme.background)
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: PingySpacing.sm) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(url: conversation.participantAvatarUrl, fallback: conversation.participantUsername)
                Circle()
                    .fill(conversation.participantIsOnline ? PingyTheme.success : Color.gray.opacity(0.45))
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.participantUsername)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : PingyTheme.textPrimary)
                    Spacer()

                    if let lastTime = conversation.lastMessageCreatedAt {
                        Text(formatTime(lastTime))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(isSelected ? .white.opacity(0.86) : PingyTheme.textSecondary)
                    }
                }

                Text(lastPreview)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : PingyTheme.textSecondary)
            }

            if conversation.unreadCount > 0 {
                Text("\(conversation.unreadCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.white.opacity(0.2) : PingyTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isSelected
                        ? LinearGradient(
                            colors: [PingyTheme.primary, PingyTheme.primaryStrong],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PingyTheme.border, lineWidth: isSelected ? 0 : 1)
        )
    }

    private var lastPreview: String {
        if let type = conversation.lastMessageType, type != "text" {
            if let mediaName = conversation.lastMessageMediaName, !mediaName.isEmpty {
                return mediaName
            }
            return type.capitalized
        }

        guard let body = conversation.lastMessageBody else {
            return "No messages yet"
        }

        if body.looksLikeEncryptedPayload {
            return "Encrypted message"
        }

        if let text = body.stringValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        return "Message"
    }

    private func formatTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "" }
        let time = DateFormatter()
        time.timeStyle = .short
        return time.string(from: date)
    }
}

private extension JSONValue {
    var looksLikeEncryptedPayload: Bool {
        if let object = objectValue {
            return object["ciphertext"]?.stringValue != nil && object["iv"]?.stringValue != nil
        }

        guard let raw = stringValue else {
            return false
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
            return false
        }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }

        return object["ciphertext"] != nil && object["iv"] != nil
    }
}
