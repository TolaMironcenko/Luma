import Foundation
import XCTest
@testable import Luma

final class CallSnapshotTests: XCTestCase {
    func testIncomingVideoCallProjection() {
        let snapshot = CallSnapshot(
            id: UUID(),
            peerJID: "alice@example.org",
            direction: .incoming,
            media: [.audio, .video],
            phase: .ringing,
            connectedAt: nil,
            isMuted: false,
            isCameraEnabled: true,
            isSpeakerEnabled: true,
            hasLocalVideo: false,
            hasRemoteVideo: false
        )

        XCTAssertTrue(snapshot.isVideoCall)
        XCTAssertTrue(snapshot.isIncomingRinging)
    }

    func testConnectedAudioCallIsNotRinging() {
        let snapshot = CallSnapshot(
            id: UUID(),
            peerJID: "bob@example.org",
            direction: .outgoing,
            media: [.audio],
            phase: .connected,
            connectedAt: Date(),
            isMuted: true,
            isCameraEnabled: false,
            isSpeakerEnabled: false,
            hasLocalVideo: false,
            hasRemoteVideo: false
        )

        XCTAssertFalse(snapshot.isVideoCall)
        XCTAssertFalse(snapshot.isIncomingRinging)
    }

    func testConnectedCallAlwaysBecomesCompletedHistory() {
        XCTAssertEqual(
            CallHistoryPolicy.outcome(
                direction: .outgoing,
                phase: .connected,
                connectedAt: Date(),
                cause: .failed
            ),
            .completed
        )
    }

    func testDeclinedCallClassification() {
        XCTAssertEqual(
            CallHistoryPolicy.outcome(
                direction: .incoming,
                phase: .ringing,
                connectedAt: nil,
                cause: .localRejected
            ),
            .declined
        )
        XCTAssertEqual(
            CallHistoryPolicy.outcome(
                direction: .outgoing,
                phase: .ringing,
                connectedAt: nil,
                cause: .remoteRejected
            ),
            .declined
        )
    }

    func testMissedCancelledAndUnansweredClassification() {
        XCTAssertEqual(
            CallHistoryPolicy.outcome(
                direction: .incoming,
                phase: .ringing,
                connectedAt: nil,
                cause: .remoteCancelled
            ),
            .missed
        )
        XCTAssertEqual(
            CallHistoryPolicy.outcome(
                direction: .outgoing,
                phase: .ringing,
                connectedAt: nil,
                cause: .localEnded
            ),
            .cancelled
        )
        XCTAssertEqual(
            CallHistoryPolicy.outcome(
                direction: .outgoing,
                phase: .ringing,
                connectedAt: nil,
                cause: .timedOut
            ),
            .unanswered
        )
        XCTAssertEqual(
            CallHistoryPolicy.outcome(
                direction: .incoming,
                phase: .connecting,
                connectedAt: nil,
                cause: .remoteEnded
            ),
            .failed
        )
    }
}
