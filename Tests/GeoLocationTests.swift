import XCTest
@testable import Luma

final class GeoLocationTests: XCTestCase {
    func testGeoURIFormattingAndParsing() throws {
        let location = try XCTUnwrap(
            GeoLocation(latitude: 59.3293, longitude: 18.0686, uncertainty: 14.4)
        )

        XCTAssertEqual(location.uriString, "geo:59.329300,18.068600;u=14")

        let decoded = try XCTUnwrap(GeoLocation(uri: location.uriString))
        XCTAssertEqual(decoded.latitude, 59.3293, accuracy: 0.000_001)
        XCTAssertEqual(decoded.longitude, 18.0686, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(decoded.uncertainty), 14, accuracy: 0.001)
    }

    func testGeoURIWithoutUncertainty() throws {
        let location = try XCTUnwrap(GeoLocation(uri: "geo:-33.8688,151.2093"))

        XCTAssertEqual(location.latitude, -33.8688, accuracy: 0.000_001)
        XCTAssertEqual(location.longitude, 151.2093, accuracy: 0.000_001)
        XCTAssertNil(location.uncertainty)
    }

    func testInvalidCoordinatesAreRejected() {
        XCTAssertNil(GeoLocation(latitude: 91, longitude: 0))
        XCTAssertNil(GeoLocation(latitude: 0, longitude: -181))
        XCTAssertNil(GeoLocation(uri: "https://maps.example.org/59,18"))
        XCTAssertNil(GeoLocation(uri: "geo:not-a-number,18"))
        XCTAssertNil(GeoLocation(uri: "geo:59,18;u=unknown"))
    }
}
