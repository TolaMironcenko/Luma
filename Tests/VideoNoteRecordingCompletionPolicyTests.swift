import AVFoundation
import XCTest
@testable import Luma

final class VideoNoteRecordingCompletionPolicyTests: XCTestCase {
    func testNilErrorKeepsRecording() {
        XCTAssertTrue(VideoNoteRecordingCompletionPolicy.shouldKeepOutput(for: nil))
    }

    func testSuccessfulFinishedFlagKeepsRecordingDespiteError() {
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: -11_800,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: true]
        )

        XCTAssertTrue(VideoNoteRecordingCompletionPolicy.shouldKeepOutput(for: error))
    }

    func testFailedFinishedFlagRejectsRecording() {
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: -11_800,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: false]
        )

        XCTAssertFalse(VideoNoteRecordingCompletionPolicy.shouldKeepOutput(for: error))
    }

    func testNSNumberSuccessfulFinishedFlagKeepsRecording() {
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: -11_800,
            userInfo: [AVErrorRecordingSuccessfullyFinishedKey: NSNumber(value: true)]
        )

        XCTAssertTrue(VideoNoteRecordingCompletionPolicy.shouldKeepOutput(for: error))
    }

    func testMaximumDurationStillKeepsRecording() {
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.maximumDurationReached.rawValue
        )

        XCTAssertTrue(VideoNoteRecordingCompletionPolicy.shouldKeepOutput(for: error))
    }

    func testExplicitStopAllowsCompletedRecordingToSend() {
        XCTAssertTrue(VideoNoteRecordingCompletionPolicy.wasRequestedOrReachedLimit(
            stopRequested: true,
            error: nil,
            recordedDuration: 3,
            maximumDuration: 60
        ))
    }

    func testUnexpectedCameraCompletionDoesNotSendPartialRecording() {
        XCTAssertFalse(VideoNoteRecordingCompletionPolicy.wasRequestedOrReachedLimit(
            stopRequested: false,
            error: nil,
            recordedDuration: 3,
            maximumDuration: 60
        ))
    }

    func testAutomaticMaximumDurationCompletionMaySend() {
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.maximumDurationReached.rawValue
        )

        XCTAssertTrue(VideoNoteRecordingCompletionPolicy.wasRequestedOrReachedLimit(
            stopRequested: false,
            error: error,
            recordedDuration: 59.8,
            maximumDuration: 60
        ))
    }
}
