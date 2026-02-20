import Foundation

@MainActor
final class CallsViewModel: ObservableObject {
    @Published var callLogs: [CallLogEntry] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let service: CallLogService

    init(service: CallLogService = .shared) {
        self.service = service
    }

    func reload(for userID: String?) async {
        guard let userID else {
            callLogs = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        callLogs = await service.list(for: userID)
    }

    func startOutgoingCall(for userID: String?, conversation: Conversation) async {
        guard let userID else { return }
        let entry = CallLogEntry(
            id: UUID().uuidString,
            conversationID: conversation.conversationId,
            participantID: conversation.participantId,
            participantName: conversation.participantUsername,
            participantAvatarURL: conversation.participantAvatarUrl,
            direction: .outgoing,
            type: .voice,
            createdAt: Date(),
            durationSeconds: 0
        )
        await service.append(entry, for: userID)
        callLogs = await service.list(for: userID)
    }

    func clear(for userID: String?) async {
        guard let userID else { return }
        await service.clear(for: userID)
        callLogs = []
    }
}
