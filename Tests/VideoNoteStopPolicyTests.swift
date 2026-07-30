import Foundation
import XCTest
@testable import Luma

final class VideoNoteStopPolicyTests: XCTestCase {
    func testEarlyReleaseWaitsForRecordedMedia() {
        let remaining = VideoNoteStopPolicy.remainingRecordedDuration(
            recordedDuration: 0.25,
            minimumDuration: VideoNoteStopPolicy.minimumCaptureDuration
        )

        XCTAssertEqual(
            remaining,
            VideoNoteStopPolicy.minimumCaptureDuration - 0.25,
            accuracy: 0.001
        )
    }

    func testStopDoesNotWaitAfterMinimumMediaDurationElapsed() {
        XCTAssertEqual(
            VideoNoteStopPolicy.remainingRecordedDuration(
                recordedDuration: 2,
                minimumDuration: VideoNoteStopPolicy.minimumCaptureDuration
            ),
            0,
            accuracy: 0.001
        )
    }

    func testRecordingFloorIsLongerThanLegacyShortClipThreshold() {
        XCTAssertGreaterThanOrEqual(VideoNoteStopPolicy.minimumCaptureDuration, 1.1)
    }

    func testRecordedMediaTimeControlsTheFinalStop() {
        XCTAssertEqual(
            VideoNoteStopPolicy.remainingRecordedDuration(
                recordedDuration: 0.35,
                minimumDuration: 1.2
            ),
            0.85,
            accuracy: 0.001
        )
        XCTAssertEqual(
            VideoNoteStopPolicy.remainingRecordedDuration(
                recordedDuration: 1.3,
                minimumDuration: 1.2
            ),
            0,
            accuracy: 0.001
        )
    }
}
