import AVFoundation
import Combine
import Foundation

@MainActor
final class WatchVoiceRecorder: NSObject, ObservableObject {
    struct Recording: Equatable {
        let url: URL
        let duration: TimeInterval
    }

    static let maximumDuration: TimeInterval = 60

    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var recording: Recording?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var startedAt: Date?

    func start() async throws {
        guard !isRecording else { return }
        discardRecording()
        guard await requestPermission() else { throw WatchVoiceRecorderError.permissionDenied }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LumaWatchRecordings", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record(forDuration: Self.maximumDuration) else {
                throw WatchVoiceRecorderError.cannotStart
            }

            self.recorder = recorder
            startedAt = Date()
            elapsed = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let startedAt = self.startedAt else { return }
                    self.elapsed = min(Date().timeIntervalSince(startedAt), Self.maximumDuration)
                    if !self.recorderIsActivelyRecording {
                        _ = try? self.finish()
                    }
                }
            }
        } catch {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    @discardableResult
    func finish() throws -> Recording {
        guard let recorder, isRecording else { throw WatchVoiceRecorderError.notRecording }
        let duration = min(max(recorder.currentTime, elapsed), Self.maximumDuration)
        let url = recorder.url
        recorder.stop()
        stopRecordingState()
        guard duration >= 0.4 else {
            try? FileManager.default.removeItem(at: url)
            throw WatchVoiceRecorderError.tooShort
        }
        let recording = Recording(url: url, duration: duration)
        self.recording = recording
        return recording
    }

    func cancelRecording() {
        let url = recorder?.url
        recorder?.stop()
        stopRecordingState()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func togglePlayback() throws {
        if isPlaying {
            stopPlayback()
            return
        }
        guard let recording else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio)
        try audioSession.setActive(true)
        do {
            let player = try AVAudioPlayer(contentsOf: recording.url)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { throw WatchVoiceRecorderError.cannotPlay }
            self.player = player
            isPlaying = true
        } catch {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func discardRecording() {
        stopPlayback()
        if let url = recording?.url {
            try? FileManager.default.removeItem(at: url)
        }
        recording = nil
    }

    func detachRecording() -> Recording? {
        stopPlayback()
        defer { recording = nil }
        return recording
    }

    func reset() {
        cancelRecording()
        discardRecording()
    }

    private var recorderIsActivelyRecording: Bool {
        recorder?.isRecording == true
    }

    private func stopRecordingState() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        startedAt = nil
        elapsed = 0
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}

extension WatchVoiceRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
        }
    }
}

private enum WatchVoiceRecorderError: LocalizedError {
    case permissionDenied
    case cannotStart
    case notRecording
    case tooShort
    case cannotPlay

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Разрешите Luma доступ к микрофону в настройках Apple Watch."
        case .cannotStart:
            return "Не удалось начать запись на Apple Watch."
        case .notRecording:
            return "Запись голосового сообщения не запущена."
        case .tooShort:
            return "Голосовое сообщение получилось слишком коротким."
        case .cannotPlay:
            return "Не удалось воспроизвести запись."
        }
    }
}
