import Foundation
import XCTest
@testable import Luma

final class VideoNoteRecordingLifecycleTests: XCTestCase {
    func testOnlyBusyPhasesBlockASecondRecording() {
        XCTAssertFalse(VideoNoteRecordingLifecycle.idle.isBusy)
        XCTAssertFalse(VideoNoteRecordingLifecycle.prepared.isBusy)
        XCTAssertTrue(VideoNoteRecordingLifecycle.starting.isBusy)
        XCTAssertTrue(VideoNoteRecordingLifecycle.recording.isBusy)
        XCTAssertTrue(VideoNoteRecordingLifecycle.stopping.isBusy)
    }

    func testStaleCompletionCannotFinishANewerRecording() {
        let oldURL = URL(fileURLWithPath: "/tmp/old.mov")
        let currentURL = URL(fileURLWithPath: "/tmp/current.mov")

        XCTAssertFalse(VideoNoteRecordingLifecycle.acceptsCompletion(
            activeURL: currentURL,
            outputURL: oldURL
        ))
        XCTAssertTrue(VideoNoteRecordingLifecycle.acceptsCompletion(
            activeURL: currentURL,
            outputURL: currentURL
        ))
    }

    func testMacOSTemporaryPathAliasesIdentifyTheSameRecording() {
        let suppliedURL = URL(fileURLWithPath: "/var/folders/luma/video-note-id.mov")
        let callbackURL = URL(fileURLWithPath: "/private/var/folders/luma/video-note-id.mov")

        XCTAssertTrue(VideoNoteRecordingLifecycle.acceptsCompletion(
            activeURL: suppliedURL,
            outputURL: callbackURL
        ))
    }

    func testTemporaryPathAliasDoesNotAcceptAnotherRecording() {
        let currentURL = URL(fileURLWithPath: "/var/folders/luma/current.mov")
        let oldURL = URL(fileURLWithPath: "/private/var/folders/luma/old.mov")

        XCTAssertFalse(VideoNoteRecordingLifecycle.acceptsCompletion(
            activeURL: currentURL,
            outputURL: oldURL
        ))
    }
}
