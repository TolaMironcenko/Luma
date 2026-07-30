import Foundation
import XCTest
@testable import Luma

final class WatchVoiceMessageTests: XCTestCase {
    func testTransferUsesStableXMPPMessageIDAcrossRetries() {
        let message = WatchVoiceMessage(
            transferID: "9B4D98BA-7EB0-487A-96A2-608052AFCA2E",
            jid: "friend@example.org",
            filename: "voice.m4a",
            duration: 2.5,
            data: Data([0x01])
        )

        XCTAssertEqual(
            message.stableMessageID,
            "watch-9B4D98BA-7EB0-487A-96A2-608052AFCA2E"
        )
    }
}
