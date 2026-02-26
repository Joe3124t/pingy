import SwiftUI

struct StarredMessagesView: View {
    let displayName: String
    let messages: [Message]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                if messages.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "star.circle")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(PingyTheme.primaryStrong)

                        Text("No starred messages")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(PingyTheme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("Tap and hold a message to star it. Starred messages will appear here.")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(PingyTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                    .padding(.horizontal, PingySpacing.md)
                } else {
                    ForEach(messages) { message in
                        starredRow(for: message)
                    }
                }
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("Starred")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
    }

    private func starredRow(for message: Message) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(messageSender(for: message))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.primaryStrong)

            Text(MessageBodyFormatter.previewText(
                from: message.body,
                fallback: MessageBodyFormatter.fallbackLabel(for: message.type, mediaName: message.mediaName)
            ))
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(PingyTheme.textPrimary)

            Text(formattedTime(message.createdAt))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PingySpacing.md)
        .pingyCard()
    }

    private func messageSender(for message: Message) -> String {
        if let sender = message.senderUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sender.isEmpty
        {
            return sender
        }

        if message.senderId == message.recipientId {
            return "Me"
        }

        return displayName
    }

    private func formattedTime(_ raw: String) -> String {
        if let date = ISO8601DateFormatter().date(from: raw) {
            return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
        }
        return raw
    }
}
