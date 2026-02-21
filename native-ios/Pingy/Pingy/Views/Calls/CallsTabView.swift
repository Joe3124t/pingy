import SwiftUI

struct CallsTabView: View {
    @ObservedObject var messengerViewModel: MessengerViewModel
    @StateObject private var viewModel = CallsViewModel()
    @State private var isPickerPresented = false
    @State private var activeCallSession: InAppCallSession?
    @State private var callAutoConnectTask: Task<Void, Never>?

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
        .navigationTitle("Calls")
        .onAppear {
            Task { await viewModel.reload(for: messengerViewModel.currentUserID) }
        }
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                callPicker
            }
        }
        .fullScreenCover(item: $activeCallSession) { session in
            InAppVoiceCallView(
                session: session,
                onToggleMute: {
                    guard var value = activeCallSession else { return }
                    value.isMuted.toggle()
                    activeCallSession = value
                },
                onToggleSpeaker: {
                    guard var value = activeCallSession else { return }
                    value.isSpeakerEnabled.toggle()
                    activeCallSession = value
                },
                onEnd: {
                    endCurrentCall()
                }
            )
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start secure call")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Text("Choose a chat contact to start a 1-to-1 voice call.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)

            Button {
                isPickerPresented = true
            } label: {
                Label("New call", systemImage: "phone.fill.badge.plus")
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
            Text("Recent")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Text("No calls yet.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pingyCard()
    }

    private var recentCallsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                Spacer()
                Button("Clear") {
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
                        startCall(for: conversation)
                    }
                } label: {
                    HStack(spacing: PingySpacing.sm) {
                        AvatarView(url: conversation.participantAvatarUrl, fallback: conversation.participantUsername, size: 44, cornerRadius: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.participantUsername)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(PingyTheme.textPrimary)
                            if conversation.participantIsOnline {
                                Text("Online")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(PingyTheme.success)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("New call")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
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
        let direction = call.direction == .outgoing ? "Outgoing" : call.direction == .incoming ? "Incoming" : "Missed"
        return "\(direction) - \(time)"
    }

    private func startCall(for conversation: Conversation) {
        guard activeCallSession == nil else { return }

        let callId = UUID().uuidString
        activeCallSession = InAppCallSession(
            id: callId,
            conversationId: conversation.conversationId,
            participantId: conversation.participantId,
            participantName: messengerViewModel.contactDisplayName(for: conversation),
            participantAvatarURL: conversation.participantAvatarUrl,
            status: .ringing,
            startedAt: nil,
            isMuted: false,
            isSpeakerEnabled: false
        )
        messengerViewModel.sendCallInvite(
            callId: callId,
            conversationId: conversation.conversationId,
            participantID: conversation.participantId
        )

        callAutoConnectTask?.cancel()
        callAutoConnectTask = Task { [conversationId = conversation.conversationId, participantId = conversation.participantId] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                guard var session = activeCallSession, session.conversationId == conversationId else { return }
                session.status = .connected
                session.startedAt = Date()
                activeCallSession = session
                messengerViewModel.sendCallAccepted(callId: session.id, conversationId: conversationId, participantID: participantId)
            }
        }
    }

    private func endCurrentCall() {
        guard let session = activeCallSession else { return }
        callAutoConnectTask?.cancel()
        messengerViewModel.sendCallEnded(
            callId: session.id,
            conversationId: session.conversationId,
            participantID: session.participantId,
            status: session.startedAt == nil ? .missed : .ended
        )
        activeCallSession = nil
    }
}
