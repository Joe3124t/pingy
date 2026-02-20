import SwiftUI

struct ContactInfoView: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss
    @State private var isMuted = false
    @State private var showBlockConfirm = false
    @State private var showClearChatConfirm = false

    private var muteKey: String {
        "pingy.chat.muted.\(conversation.conversationId)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                profileCard
                mediaCard
                actionsCard
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("Contact Info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .onAppear {
            isMuted = UserDefaults.standard.bool(forKey: muteKey)
        }
        .onChange(of: isMuted) { newValue in
            UserDefaults.standard.set(newValue, forKey: muteKey)
        }
        .confirmationDialog("Block this contact?", isPresented: $showBlockConfirm) {
            Button("Block", role: .destructive) {
                Task {
                    await viewModel.blockSelectedUser()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear chat for your account?", isPresented: $showClearChatConfirm) {
            Button("Clear chat", role: .destructive) {
                Task {
                    await viewModel.deleteSelectedConversation(forEveryone: false)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var profileCard: some View {
        VStack(spacing: 12) {
            AvatarView(
                url: conversation.participantAvatarUrl,
                fallback: contactDisplayName,
                size: 92,
                cornerRadius: 46
            )

            Text(contactDisplayName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
                .multilineTextAlignment(.center)

            if contactDisplayName != conversation.participantUsername {
                Text(conversation.participantUsername)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            }

            Text(contactPhoneNumber)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .pingyCard()
    }

    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Media, Links & Docs")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            infoRow(title: "Media", value: "\(mediaCount)")
            infoRow(title: "Links", value: "\(linksCount)")
            infoRow(title: "Documents", value: "\(documentCount)")
        }
        .pingyCard()
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Toggle("Mute notifications", isOn: $isMuted)
                .tint(PingyTheme.primary)

            Button {
                showBlockConfirm = true
            } label: {
                Label("Block", systemImage: "hand.raised.fill")
                    .foregroundStyle(PingyTheme.warning)
            }
            .buttonStyle(PingyPressableButtonStyle())

            Button {
                showClearChatConfirm = true
            } label: {
                Label("Clear chat", systemImage: "trash")
                    .foregroundStyle(PingyTheme.danger)
            }
            .buttonStyle(PingyPressableButtonStyle())

            ShareLink(item: exportedChatText) {
                Label("Export chat", systemImage: "square.and.arrow.up")
                    .foregroundStyle(PingyTheme.primaryStrong)
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private var contactDisplayName: String {
        viewModel.contactDisplayName(for: conversation)
    }

    private var contactPhoneNumber: String {
        let fallback = "Phone number hidden"
        guard let value = viewModel.contactPhoneNumber(for: conversation.participantId),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return fallback
        }
        return value
    }

    private var messages: [Message] {
        viewModel.messages(for: conversation.conversationId)
    }

    private var mediaCount: Int {
        messages.filter { $0.type == .image || $0.type == .video || $0.type == .voice }.count
    }

    private var documentCount: Int {
        messages.filter { $0.type == .file }.count
    }

    private var linksCount: Int {
        messages.reduce(into: 0) { partial, message in
            guard let text = message.body?.stringValue?.lowercased() else { return }
            if text.contains("http://") || text.contains("https://") {
                partial += 1
            }
        }
    }

    private var exportedChatText: String {
        let formatter = ISO8601DateFormatter()
        let rows = messages.map { message in
            let dateLabel: String
            if let date = formatter.date(from: message.createdAt) {
                let output = DateFormatter()
                output.dateStyle = .short
                output.timeStyle = .short
                dateLabel = output.string(from: date)
            } else {
                dateLabel = message.createdAt
            }
            let sender = message.senderUsername ?? (message.senderId == viewModel.currentUserID ? "Me" : contactDisplayName)
            let content = message.body?.stringValue ?? message.mediaName ?? message.type.rawValue.capitalized
            return "[\(dateLabel)] \(sender): \(content)"
        }

        return rows.joined(separator: "\n")
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
        }
    }
}
