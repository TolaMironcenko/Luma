import XCTest
@testable import Luma

final class MediaSendActivityTrackerTests: XCTestCase {
    func testOverlappingOperationsDoNotRestoreStaleBusyState() {
        var tracker = MediaSendActivityTracker()

        let first = tracker.begin()
        let second = tracker.begin()
        XCTAssertTrue(tracker.isActive)

        tracker.end(first)
        XCTAssertTrue(tracker.isActive)

        tracker.end(second)
        XCTAssertFalse(tracker.isActive)
    }

    func testEndingSameOperationTwiceIsSafe() {
        var tracker = MediaSendActivityTracker()
        let token = tracker.begin()

        tracker.end(token)
        tracker.end(token)

        XCTAssertFalse(tracker.isActive)
        XCTAssertTrue(tracker.activeTokens.isEmpty)
    }

    func testResetRecoversFromEveryOutstandingOperation() {
        var tracker = MediaSendActivityTracker()
        _ = tracker.begin()
        _ = tracker.begin()

        tracker.reset()

        XCTAssertFalse(tracker.isActive)
    }
}
