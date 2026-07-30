import Foundation

enum CallMedia: String, CaseIterable, Hashable, Sendable {
    case audio
    case video
}

enum CallDirection: String, Equatable, Sendable {
    case incoming
    case outgoing
}

enum CallPhase: Equatable, Sendable {
    case ringing
    case connecting
    case connected
}

/// Stable value stored with a local call-history message.
enum CallHistoryOutcome: String, Codable, Hashable, Sendable {
    case completed
    case declined
    case missed
    case cancelled
    case unanswered
    case failed
    case answeredElsewhere
}

struct CallHistoryMetadata: Codable, Hashable, Sendable {
    let isVideo: Bool
    let outcome: CallHistoryOutcome
}

/// Internal reason used to turn every call-ending path into one history result.
enum CallTerminationCause: Equatable, Sendable {
    case localEnded
    case localRejected
    case remoteEnded
    case remoteRejected
    case remoteCancelled
    case timedOut
    case failed
    case connectionDetached
    case answeredElsewhere
}

struct CallHistoryEntry: Equatable, Sendable {
    let id: String
    let peerJID: String
    let direction: CallDirection
    let isVideo: Bool
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval?
    let outcome: CallHistoryOutcome
}

/// Pure classification kept outside WebRTC so every termination scenario can
/// be tested without constructing a live peer connection.
enum CallHistoryPolicy {
    static func outcome(
        direction: CallDirection,
        phase: CallPhase,
        connectedAt: Date?,
        cause: CallTerminationCause
    ) -> CallHistoryOutcome {
        // Once media connected, a later hang-up or transport loss still belongs
        // to the successful-call history and keeps its measured duration.
        if connectedAt != nil || phase == .connected {
            return .completed
        }

        switch cause {
        case .localRejected, .remoteRejected:
            return .declined
        case .localEnded:
            return .cancelled
        case .remoteCancelled, .remoteEnded:
            guard phase == .ringing else { return .failed }
            return direction == .incoming ? .missed : .declined
        case .timedOut:
            guard phase == .ringing else { return .failed }
            return direction == .incoming ? .missed : .unanswered
        case .answeredElsewhere:
            return .answeredElsewhere
        case .failed, .connectionDetached:
            return .failed
        }
    }
}

/// Value-type projection of the live WebRTC/Jingle session used by SwiftUI.
struct CallSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let peerJID: String
    let direction: CallDirection
    let media: Set<CallMedia>
    let phase: CallPhase
    let connectedAt: Date?
    let isMuted: Bool
    let isCameraEnabled: Bool
    let isSpeakerEnabled: Bool
    let hasLocalVideo: Bool
    let hasRemoteVideo: Bool

    var isVideoCall: Bool {
        media.contains(.video)
    }

    var isIncomingRinging: Bool {
        direction == .incoming && phase == .ringing
    }
}
