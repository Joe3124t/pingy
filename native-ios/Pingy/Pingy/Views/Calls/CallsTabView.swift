import SwiftUI

struct CallsTabView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @StateObject private var viewModel = CallsViewModel()
    @State private var isPickerPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                actionCard

                if viewModel.callLogs.isEmpty {
                    emptyStateCard
                } else {
                    recentCallsCard
                }
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Calls"))
        .onAppear {
            Task { await viewModel.reload(for: messengerViewModel.currentUserID) }
        }
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                callPicker
            }
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Start secure call"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Text(String(localized: "Choose a chat contact to start a 1-to-1 voice call."))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)

            Button {
                isPickerPresented = true
            } label: {
                Label(String(localized: "New call"), systemImage: "phone.fill.badge.plus")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(PingyTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Recent"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Text(String(localized: "No calls yet."))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pingyCard()
    }

    private var recentCallsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Recent"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                Spacer()
                Button(String(localized: "Clear")) {
                    Task { await viewModel.clear(for: messengerViewModel.currentUserID) }
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.danger)
            }

            ForEach(viewModel.callLogs.prefix(30)) { call in
                HStack(spacing: PingySpacing.sm) {
                    AvatarView(url: call.participantAvatarURL, fallback: call.participantName, size: 44, cornerRadius: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.participantName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(PingyTheme.textPrimary)

                        Text(callDetail(call))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PingyTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PingyTheme.primaryStrong)
                }
                .padding(.vertical, 4)
            }
        }
        .pingyCard()
    }

    private var callPicker: some View {
        List {
            ForEach(messengerViewModel.conversations.filter { !$0.isBlocked }) { conversation in
                Button {
                    Task {
                        await viewModel.startOutgoingCall(
                            for: messengerViewModel.currentUserID,
                            conversation: conversation
                        )
                        isPickerPresented = false
                        messengerViewModel.startCall(from: conversation)
                    }
                } label: {
                    HStack(spacing: PingySpacing.sm) {
                        AvatarView(url: conversation.participantAvatarUrl, fallback: conversation.participantUsername, size: 44, cornerRadius: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.participantUsername)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(PingyTheme.textPrimary)
                            if conversation.participantIsOnline {
                                Text(String(localized: "Online"))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(PingyTheme.success)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "New call"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: "Close")) {
                    isPickerPresented = false
                }
            }
        }
    }

    private func callDetail(_ call: CallLogEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: call.createdAt)
        let direction = call.direction == .outgoing
            ? String(localized: "Outgoing")
            : call.direction == .incoming
                ? String(localized: "Incoming")
                : String(localized: "Missed")
        return "\(direction) - \(time)"
    }

}
