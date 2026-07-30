import Foundation
import XCTest
@testable import Luma

final class MessageCorrectionTests: XCTestCase {
    func testOnlyDeliveredOrSentOutgoingTextCanBeEdited() {
        let editable = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "До исправления",
            direction: .outgoing,
            delivery: .sent,
            security: .omemo
        )
        var incoming = editable
        incoming.direction = .incoming
        var attachment = editable
        attachment.kind = .attachment
        var failed = editable
        failed.delivery = .failed
        var retracted = editable
        retracted.retractedAt = Date()

        XCTAssertTrue(editable.canBeEdited)
        XCTAssertFalse(incoming.canBeEdited)
        XCTAssertFalse(attachment.canBeEdited)
        XCTAssertFalse(failed.canBeEdited)
        XCTAssertFalse(retracted.canBeEdited)
    }

    func testEditedTimestampRoundTrips() throws {
        let editedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let message = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "После исправления",
            direction: .outgoing,
            delivery: .delivered,
            security: .plaintext,
            editedAt: editedAt
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.editedAt, editedAt)
    }

    func testLegacyMessageWithoutEditedTimestampStillDecodes() throws {
        let message = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "Старое сообщение",
            direction: .incoming,
            delivery: .delivered,
            security: .omemo
        )
        let encoded = try JSONEncoder().encode(message)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "editedAt")

        let decoded = try JSONDecoder().decode(
            ChatMessage.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.editedAt)
    }
}
