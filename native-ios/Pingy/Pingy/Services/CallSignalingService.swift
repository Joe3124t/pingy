import AVFoundation
import Combine
import Foundation

@MainActor
final class CallSignalingService: ObservableObject {
    enum CallDirection: String, Codable {
        case incoming
        case outgoing
    }

    struct CallParticipantProfile: Equatable {
        let conversationId: String
        let participantId: String
        let displayName: String
        let avatarURL: String?
    }

    struct CallSession: Identifiable, Equatable {
        let id: String
        let conversationId: String
        let participantId: String
        let participantName: String
        let participantAvatarURL: String?
        let direction: CallDirection
        var status: CallSignalStatus
        var startedAt: Date?
        var isMuted: Bool
        var isSpeakerEnabled: Bool
        var createdAt: Date
    }

    @Published private(set) var activeSession: CallSession?
    var onRingingTimeout: ((CallSession) -> Void)?

    private var ringingTimeoutTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?

    func beginOutgoingCall(profile: CallParticipantProfile, callId: String) {
        cancelTasks()
        activeSession = CallSession(
            id: callId,
            conversationId: profile.conversationId,
            participantId: profile.participantId,
            participantName: profile.displayName,
            participantAvatarURL: profile.avatarURL,
            direction: .outgoing,
            status: .ringing,
            startedAt: nil,
            isMuted: false,
            isSpeakerEnabled: false,
            createdAt: Date()
        )
        scheduleRingingTimeout(for: callId)
    }

    func handleSignal(
        _ event: CallSignalEvent,
        currentUserID: String,
        profile: CallParticipantProfile?
    ) {
        guard !currentUserID.isEmpty else { return }
        guard event.fromUserId == currentUserID || event.toUserId == currentUserID else { return }

        let participantId = event.fromUserId == currentUserID ? event.toUserId : event.fromUserId
        let resolvedProfile: CallParticipantProfile = profile ?? CallParticipantProfile(
            conversationId: event.conversationId,
            participantId: participantId,
            displayName: "Pingy User",
            avatarURL: nil
        )

        if activeSession == nil {
            if event.status == .ringing, event.toUserId == currentUserID {
                activeSession = CallSession(
                    id: event.callId,
                    conversationId: event.conversationId,
                    participantId: participantId,
                    participantName: resolvedProfile.displayName,
                    participantAvatarURL: resolvedProfile.avatarURL,
                    direction: .incoming,
                    status: .ringing,
                    startedAt: nil,
                    isMuted: false,
                    isSpeakerEnabled: false,
                    createdAt: Date()
                )
                scheduleRingingTimeout(for: event.callId)
            }
            return
        }

        guard var current = activeSession else { return }
        guard current.id == event.callId || current.conversationId == event.conversationId else { return }

        if current.participantName == "Pingy User", !resolvedProfile.displayName.isEmpty {
            current = CallSession(
                id: current.id,
                conversationId: current.conversationId,
                participantId: current.participantId,
                participantName: resolvedProfile.displayName,
                participantAvatarURL: resolvedProfile.avatarURL,
                direction: current.direction,
                status: current.status,
                startedAt: current.startedAt,
                isMuted: current.isMuted,
                isSpeakerEnabled: current.isSpeakerEnabled,
                createdAt: current.createdAt
            )
        }

        switch event.status {
        case .ringing:
            current.status = .ringing
            activeSession = current
            scheduleRingingTimeout(for: current.id)
        case .connected:
            current.status = .connected
            current.startedAt = current.startedAt ?? Date()
            activeSession = current
            activateAudioSessionIfNeeded(speakerEnabled: current.isSpeakerEnabled)
            cancelRingingTimeout()
        case .declined, .ended, .missed:
            current.status = event.status
            activeSession = current
            deactivateAudioSession()
            cancelRingingTimeout()
            scheduleAutoDismiss()
        }
    }

    func acceptCurrentCall() {
        guard var session = activeSession else { return }
        session.status = .connected
        session.startedAt = session.startedAt ?? Date()
        activeSession = session
        activateAudioSessionIfNeeded(speakerEnabled: session.isSpeakerEnabled)
        cancelRingingTimeout()
    }

    func declineCurrentCall() {
        guard var session = activeSession else { return }
        session.status = .declined
        activeSession = session
        deactivateAudioSession()
        cancelRingingTimeout()
        scheduleAutoDismiss()
    }

    func endCurrentCall(status: CallSignalStatus) {
        guard var session = activeSession else { return }
        session.status = status
        activeSession = session
        deactivateAudioSession()
        cancelRingingTimeout()
        scheduleAutoDismiss()
    }

    func toggleMute() {
        guard var session = activeSession else { return }
        session.isMuted.toggle()
        activeSession = session
    }

    func toggleSpeaker() {
        guard var session = activeSession else { return }
        session.isSpeakerEnabled.toggle()
        activeSession = session
        guard session.status == .connected else { return }
        activateAudioSessionIfNeeded(speakerEnabled: session.isSpeakerEnabled)
    }

    func dismissCallUI() {
        cancelTasks()
        deactivateAudioSession()
        activeSession = nil
    }

    private func scheduleRingingTimeout(for callId: String) {
        ringingTimeoutTask?.cancel()
        ringingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, var session = self.activeSession else { return }
                guard session.id == callId, session.status == .ringing else { return }
                session.status = .missed
                self.activeSession = session
                self.onRingingTimeout?(session)
                self.scheduleAutoDismiss()
            }
        }
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.activeSession = nil
            }
        }
    }

    private func cancelRingingTimeout() {
        ringingTimeoutTask?.cancel()
        ringingTimeoutTask = nil
    }

    private func cancelTasks() {
        ringingTimeoutTask?.cancel()
        ringingTimeoutTask = nil
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }

    private func activateAudioSessionIfNeeded(speakerEnabled: Bool) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(speakerEnabled ? .speaker : .none)
        } catch {
            AppLogger.error("Call audio session activation failed: \(error.localizedDescription)")
        }
    }

    private func deactivateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.overrideOutputAudioPort(.none)
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLogger.error("Call audio session deactivation failed: \(error.localizedDescription)")
        }
    }
}
