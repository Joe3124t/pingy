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
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileToolbarAvatarButton(viewModel: viewModel)
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
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileToolbarAvatarButton(viewModel: viewModel)
                }
            }
        } detail: {
            if let conversation = viewModel.selectedConversation {
                ChatDetailView(viewModel: viewModel, conversation: conversation)
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
            searchField

            if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if viewModel.isSyncingContacts {
                    ProgressView("Syncing contacts...")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PingySpacing.sm)
                        .padding(.top, PingySpacing.sm)
                } else if let hint = viewModel.contactSearchHint {
                    contactSyncHintView(hint)
                } else if !viewModel.contactSearchResults.isEmpty {
                    List(viewModel.contactSearchResults) { result in
                        Button {
                            onSelectSearchUser(result.user)
                        } label: {
                            HStack(spacing: PingySpacing.sm) {
                                AvatarView(url: result.user.avatarUrl, fallback: result.contactName, size: 48, cornerRadius: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.contactName)
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(PingyTheme.textPrimary)
                                    Text(result.user.username)
                                        .font(.system(.subheadline, design: .rounded))
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
                } else {
                    Text("No matching contacts found on Pingy.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PingySpacing.sm)
                        .padding(.top, PingySpacing.sm)
                }
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

    private var searchField: some View {
        HStack(spacing: PingySpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PingyTheme.textSecondary)

            TextField("Search contacts", text: $viewModel.searchQuery)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: viewModel.searchQuery) { _ in
                    Task { await viewModel.searchUsers() }
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
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

    private func contactSyncHintView(_ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hint)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)

            if hint.lowercased().contains("enable contact access") {
                Button("Enable contacts") {
                    Task {
                        await viewModel.requestContactAccessAndSync()
                    }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(PingyTheme.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PingySpacing.sm)
        .padding(.top, PingySpacing.sm)
    }
}

private struct ConversationDetailHost: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversationID: String

    var body: some View {
        Group {
            if let conversation = viewModel.conversations.first(where: { $0.conversationId == conversationID }) {
                ChatDetailView(viewModel: viewModel, conversation: conversation)
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
                    .overlay(Circle().stroke(PingyTheme.surface, lineWidth: 2))
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
                    .background(isSelected ? Color.white.opacity(0.24) : PingyTheme.primaryStrong)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(
                            colors: [PingyTheme.sentBubbleStart, PingyTheme.sentBubbleEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(PingyTheme.surface)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PingyTheme.border.opacity(isSelected ? 0 : 0.3), lineWidth: isSelected ? 0 : 1)
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

private struct ProfileToolbarAvatarButton: View {
    @ObservedObject var viewModel: MessengerViewModel

    var body: some View {
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
