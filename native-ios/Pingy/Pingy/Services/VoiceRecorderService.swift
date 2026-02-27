import AVFoundation
import Foundation

@MainActor
final class VoiceRecorderService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartDate: Date?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() async throws {
        let granted = await requestPermission()
        guard granted else {
            throw APIError.server(statusCode: 403, message: "Microphone permission is required")
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let outputURL = Self.makeTemporaryURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder?.delegate = self
        recorder?.record()
        recordingStartDate = Date()
        recordingDuration = 0
        isRecording = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let recordingStartDate else { return }
            self.recordingDuration = Date().timeIntervalSince(recordingStartDate)
        }
    }

    func stopRecording() throws -> (url: URL, durationMs: Int) {
        guard let recorder else {
            throw APIError.server(statusCode: 400, message: "No active recording")
        }

        recorder.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false

        let duration = Int(max(0, recordingDuration) * 1000)
        let url = recorder.url
        self.recorder = nil
        recordingDuration = 0
        recordingStartDate = nil
        deactivateAudioSession()

        return (url, duration)
    }

    func cancelRecording() {
        recorder?.stop()
        if let url = recorder?.url {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        timer?.invalidate()
        timer = nil
        recordingDuration = 0
        recordingStartDate = nil
        isRecording = false
        deactivateAudioSession()
    }

    private static func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
