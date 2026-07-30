import CoreGraphics
import XCTest
@testable import Luma

final class ComposerRecordingGestureTests: XCTestCase {
    func testShortMovementKeepsRecording() {
        XCTAssertEqual(
            ComposerRecordingGesturePolicy.resolution(
                for: CGSize(width: -35, height: -24)
            ),
            .continueRecording
        )
    }

    func testHorizontalSwipeCancelsRecording() {
        XCTAssertEqual(
            ComposerRecordingGesturePolicy.resolution(
                for: CGSize(width: -110, height: -18)
            ),
            .cancel
        )
    }

    func testVerticalSwipeLocksRecording() {
        XCTAssertEqual(
            ComposerRecordingGesturePolicy.resolution(
                for: CGSize(width: -12, height: -95)
            ),
            .lock
        )
    }

    func testDominantDiagonalDirectionWins() {
        XCTAssertEqual(
            ComposerRecordingGesturePolicy.resolution(
                for: CGSize(width: -105, height: -82)
            ),
            .cancel
        )
        XCTAssertEqual(
            ComposerRecordingGesturePolicy.resolution(
                for: CGSize(width: -94, height: -105)
            ),
            .lock
        )
    }

    func testCancelHintOpacityUsesCGFloatMathAndReturnsDouble() {
        XCTAssertEqual(
            ComposerRecordingGesturePolicy.cancelHintOpacity(for: .zero),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ComposerRecordingGesturePolicy.cancelHintOpacity(
                for: CGSize(width: -75, height: 0)
            ),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ComposerRecordingGesturePolicy.cancelHintOpacity(
                for: CGSize(width: -200, height: 0)
            ),
            0.28,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ComposerRecordingGesturePolicy.cancelHintOpacity(
                for: CGSize(width: 50, height: 0)
            ),
            1,
            accuracy: 0.0001
        )
    }

    func testDelayedMainActorStillRecognizesPhysicalLongPress() {
        XCTAssertFalse(ComposerRecordingGesturePolicy.isLongPress(elapsed: 0.1))
        XCTAssertTrue(ComposerRecordingGesturePolicy.isLongPress(elapsed: 0.3))
    }
}
