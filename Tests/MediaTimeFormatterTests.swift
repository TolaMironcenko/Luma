import XCTest
@testable import Luma

final class MediaTimeFormatterTests: XCTestCase {
    func testFormatsShortAndLongMediaDurations() {
        XCTAssertEqual(MediaTimeFormatter.string(0), "0:00")
        XCTAssertEqual(MediaTimeFormatter.string(65.9), "1:05")
        XCTAssertEqual(MediaTimeFormatter.string(3_661), "1:01:01")
    }

    func testInvalidDurationFallsBackToZero() {
        XCTAssertEqual(MediaTimeFormatter.string(.infinity), "0:00")
        XCTAssertEqual(MediaTimeFormatter.string(-4), "0:00")
    }
}
