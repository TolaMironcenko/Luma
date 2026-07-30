import CoreGraphics
import XCTest
@testable import Luma

final class MediaViewerDismissGestureTests: XCTestCase {
    func testLongDownwardSwipeDismissesViewer() {
        XCTAssertTrue(
            MediaViewerDismissGesturePolicy.shouldDismiss(
                translation: CGSize(width: 12, height: 130),
                predictedEndTranslation: CGSize(width: 14, height: 168),
                containerHeight: 800
            )
        )
    }

    func testLongUpwardSwipeDismissesViewer() {
        XCTAssertTrue(
            MediaViewerDismissGesturePolicy.shouldDismiss(
                translation: CGSize(width: -9, height: -130),
                predictedEndTranslation: CGSize(width: -12, height: -176),
                containerHeight: 800
            )
        )
    }

    func testFastShortVerticalFlickDismissesViewer() {
        XCTAssertTrue(
            MediaViewerDismissGesturePolicy.shouldDismiss(
                translation: CGSize(width: 5, height: 54),
                predictedEndTranslation: CGSize(width: 9, height: 180),
                containerHeight: 800
            )
        )
    }

    func testShortVerticalDragReturnsToViewer() {
        XCTAssertFalse(
            MediaViewerDismissGesturePolicy.shouldDismiss(
                translation: CGSize(width: 6, height: 52),
                predictedEndTranslation: CGSize(width: 8, height: 84),
                containerHeight: 800
            )
        )
    }

    func testHorizontalMediaGestureDoesNotDismissViewer() {
        XCTAssertFalse(
            MediaViewerDismissGesturePolicy.shouldDismiss(
                translation: CGSize(width: 190, height: 72),
                predictedEndTranslation: CGSize(width: 260, height: 110),
                containerHeight: 800
            )
        )
    }
}
