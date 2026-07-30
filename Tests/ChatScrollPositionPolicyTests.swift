import XCTest
@testable import Luma

final class ChatScrollPositionPolicyTests: XCTestCase {
    func testBottomSentinelCrossesOnlyTheTelegramButtonThreshold() {
        XCTAssertTrue(ChatScrollPositionPolicy.isNearBottom(
            bottomY: 796,
            viewportHeight: 700
        ))
        XCTAssertFalse(ChatScrollPositionPolicy.isNearBottom(
            bottomY: 797,
            viewportHeight: 700
        ))
    }

    func testInvalidFirstLayoutDoesNotFlashTheButton() {
        XCTAssertTrue(ChatScrollPositionPolicy.isNearBottom(
            bottomY: 0,
            viewportHeight: 0
        ))
    }

    func testNativeScrollDistanceCanHideAndRestoreButtonRepeatedly() {
        XCTAssertFalse(ChatScrollPositionPolicy.isNearBottom(distanceFromBottom: 180))
        XCTAssertTrue(ChatScrollPositionPolicy.isNearBottom(distanceFromBottom: 0))
        XCTAssertFalse(ChatScrollPositionPolicy.isNearBottom(distanceFromBottom: 220))
        XCTAssertTrue(ChatScrollPositionPolicy.isNearBottom(distanceFromBottom: -12))
    }
}
