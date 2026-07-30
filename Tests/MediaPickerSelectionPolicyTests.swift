import XCTest
@testable import Luma

final class MediaPickerSelectionPolicyTests: XCTestCase {
    func testLivePhotoPrefersStillImageButRetainsVideoFallback() {
        XCTAssertEqual(
            MediaPickerSelectionPolicy.preferredOrder(
                supportsImage: true,
                supportsVideo: true
            ),
            [.photo, .video]
        )
    }

    func testVideoOnlyAssetPrefersMovieButRetainsPhotoFallback() {
        XCTAssertEqual(
            MediaPickerSelectionPolicy.preferredOrder(
                supportsImage: false,
                supportsVideo: true
            ),
            [.video, .photo]
        )
    }
}
