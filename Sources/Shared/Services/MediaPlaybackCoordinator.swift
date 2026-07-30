import AVFoundation
import Combine
import Foundation

extension Notification.Name {
    static let lumaExclusiveMediaPlayback = Notification.Name("app.luma.exclusiveMediaPlayback")
}

@MainActor
final class MediaPlaybackCoordinator: ObservableObject {
    @Published private(set) var currentMessageID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var voiceRate: Double = 1

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var currentIsVoice = false
    private var durationTask: Task<Void, Never>?

    deinit {
        durationTask?.cancel()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func toggle(
        messageID: String,
        url: URL,
        durationHint: TimeInterval?,
        isVoice: Bool
    ) {
        if currentMessageID != messageID {
            prepare(
                messageID: messageID,
                url: url,
                durationHint: durationHint,
                isVoice: isVoice
            )
        }
        guard player != nil else { return }
        isPlaying ? pause() : play()
    }

    func seek(
        messageID: String,
        url: URL,
        durationHint: TimeInterval?,
        isVoice: Bool,
        fraction: Double
    ) {
        if currentMessageID != messageID {
            prepare(
                messageID: messageID,
                url: url,
                durationHint: durationHint,
                isVoice: isVoice
            )
        }
        guard let player else { return }
        let targetDuration = max(duration, durationHint ?? 0)
        guard targetDuration > 0 else { return }
        let seconds = max(0, min(1, fraction)) * targetDuration
        currentTime = seconds
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func cycleVoiceRate() {
        if voiceRate < 1.25 {
            voiceRate = 1.5
        } else if voiceRate < 1.75 {
            voiceRate = 2
        } else {
            voiceRate = 1
        }
        guard currentIsVoice, isPlaying else { return }
        player?.playImmediately(atRate: Float(voiceRate))
    }

    func stop() {
        durationTask?.cancel()
        durationTask = nil
        player?.pause()
        removeObservers()
        player = nil
        currentMessageID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentIsVoice = false
    }

    private func prepare(
        messageID: String,
        url: URL,
        durationHint: TimeInterval?,
        isVoice: Bool
    ) {
        stop()
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        self.player = player
        currentMessageID = messageID
        currentIsVoice = isVoice
        currentTime = 0
        duration = Self.validDuration(durationHint) ?? 0
        installObservers(for: player)

        if duration == 0 {
            durationTask = Task { [weak self] in
                let asset = AVURLAsset(url: url)
                guard let time = try? await asset.load(.duration),
                      !Task.isCancelled else { return }
                let seconds = time.seconds
                guard seconds.isFinite, seconds > 0,
                      self?.currentMessageID == messageID else { return }
                self?.duration = seconds
            }
        }
    }

    private func play() {
        guard let player, let currentMessageID else { return }
        configureAudioSession()
        NotificationCenter.default.post(
            name: .lumaExclusiveMediaPlayback,
            object: currentMessageID
        )
        if currentIsVoice {
            player.playImmediately(atRate: Float(voiceRate))
        } else {
            player.play()
        }
        isPlaying = true
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    private func installObservers(for player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            Task { @MainActor in
                guard let self, let player else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = max(0, seconds)
                }
                if let itemDuration = player.currentItem?.duration.seconds,
                   itemDuration.isFinite,
                   itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor in
                player?.seek(to: .zero)
                self?.currentTime = 0
                self?.isPlaying = false
            }
        }
    }

    private func removeObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func configureAudioSession() {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let mode: AVAudioSession.Mode = currentIsVoice ? .spokenAudio : .default
        try? session.setCategory(.playback, mode: mode, options: [.allowAirPlay, .allowBluetoothA2DP])
        try? session.setActive(true)
#endif
    }

    private static func validDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
