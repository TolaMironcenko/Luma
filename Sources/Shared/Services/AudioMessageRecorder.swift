import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioMessageRecorder: NSObject, ObservableObject {
    struct Recording {
        let url: URL
        let duration: TimeInterval
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?

    func start() async throws {
        guard !isRecording else { return }
        guard await requestPermission() else { throw AudioRecorderError.permissionDenied }
        guard !Task.isCancelled else { throw CancellationError() }
        var didStart = false
        defer {
#if os(iOS)
            if !didStart {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
#endif
        }

#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
#endif

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else { throw AudioRecorderError.cannotStart }

        self.recorder = recorder
        startedAt = Date()
        elapsed = 0
        isRecording = true
        didStart = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    func finish() throws -> Recording {
        guard let recorder, isRecording else { throw AudioRecorderError.notRecording }
        let duration = max(recorder.currentTime, elapsed)
        let url = recorder.url
        recorder.stop()
        stopState()
        guard duration >= 0.4 else {
            try? FileManager.default.removeItem(at: url)
            throw AudioRecorderError.tooShort
        }
        return Recording(url: url, duration: duration)
    }

    func cancel() {
        let url = recorder?.url
        recorder?.stop()
        stopState()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func stopState() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        startedAt = nil
        elapsed = 0
        isRecording = false
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }

    private func requestPermission() async -> Bool {
#if os(iOS)
        let session = AVAudioApplication.shared
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default:
            return false
        }
#else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
#endif
    }
}

private enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case cannotStart
    case notRecording
    case tooShort

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Разрешите Luma доступ к микрофону в системных настройках."
        case .cannotStart:
            return "Не удалось начать запись голоса."
        case .notRecording:
            return "Запись голоса не запущена."
        case .tooShort:
            return "Голосовое сообщение получилось слишком коротким."
        }
    }
}
