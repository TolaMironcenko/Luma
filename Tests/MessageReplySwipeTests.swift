import CoreGraphics
import XCTest
@testable import Luma

final class MessageReplySwipeTests: XCTestCase {
    func testHorizontalSwipeInEitherDirectionReplies() {
        XCTAssertTrue(MessageReplySwipePolicy.shouldReply(
            translation: CGSize(width: 70, height: 8),
            predictedEndTranslation: CGSize(width: 72, height: 9)
        ))
        XCTAssertTrue(MessageReplySwipePolicy.shouldReply(
            translation: CGSize(width: -70, height: 8),
            predictedEndTranslation: CGSize(width: -72, height: 9)
        ))
    }

    func testVerticalTimelineScrollDoesNotReply() {
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(
            translation: CGSize(width: 42, height: 80),
            predictedEndTranslation: CGSize(width: 50, height: 105)
        ))
    }

    func testDiagonalTimelineScrollDoesNotReply() {
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(
            translation: CGSize(width: 54, height: 44),
            predictedEndTranslation: CGSize(width: 76, height: 58)
        ))
        XCTAssertEqual(
            MessageReplySwipePolicy.offset(for: CGSize(width: 54, height: 44)),
            0
        )
    }

    func testShortSwipeDoesNotReply() {
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(
            translation: CGSize(width: 36, height: 4),
            predictedEndTranslation: CGSize(width: 48, height: 5)
        ))
    }

    func testFastHorizontalFlickUsesPredictedEnd() {
        XCTAssertTrue(MessageReplySwipePolicy.shouldReply(
            translation: CGSize(width: -35, height: 3),
            predictedEndTranslation: CGSize(width: -90, height: 7)
        ))
    }

    func testVisualOffsetIsCapped() {
        XCTAssertEqual(
            MessageReplySwipePolicy.offset(for: CGSize(width: 500, height: 0)),
            MessageReplySwipePolicy.maximumOffset
        )
    }
}
