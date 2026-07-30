import XCTest
@testable import Luma

final class AccountConfigurationTests: XCTestCase {
    func testValidAccountIsNormalized() throws {
        let account = AccountConfiguration(
            jid: "  Alice@Example.ORG  ",
            resource: "",
            manualHost: " xmpp.example.org ",
            manualPort: 5222
        )

        let validated = try account.validated()

        XCTAssertEqual(validated.normalizedJID, "alice@example.org")
        XCTAssertEqual(validated.domain, "example.org")
        XCTAssertEqual(validated.effectiveResource, "Luma")
        XCTAssertEqual(validated.manualHost, "xmpp.example.org")
    }

    func testInvalidJIDIsRejected() {
        XCTAssertThrowsError(try AccountConfiguration(jid: "not-a-jid").validated())
        XCTAssertThrowsError(try AccountConfiguration(jid: "@example.org").validated())
        XCTAssertThrowsError(try AccountConfiguration(jid: "alice@").validated())
    }

    func testInvalidPortIsRejected() {
        XCTAssertThrowsError(
            try AccountConfiguration(jid: "alice@example.org", manualPort: 70_000).validated()
        )
    }
}

