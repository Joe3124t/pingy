import AVFoundation
import Foundation

extension Notification.Name {
    static let pingyVoicePlaybackDidChange = Notification.Name("pingy.voice.playback.didChange")
}

final class VoicePlayerEngine {
    static let shared = VoicePlayerEngine()

    private init() {}

    func beginPlayback(id: String) {
        NotificationCenter.default.post(
            name: .pingyVoicePlaybackDidChange,
            object: id
        )
    }

    func stopPlayback(id: String?) {
        NotificationCenter.default.post(
            name: .pingyVoicePlaybackDidChange,
            object: id
        )
    }

    func configurePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .default,
            options: [.allowBluetooth, .allowAirPlay, .defaultToSpeaker]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
