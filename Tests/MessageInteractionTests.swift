import Foundation
import XCTest
@testable import Luma

final class MessageInteractionTests: XCTestCase {
    func testReplyMetadataRoundTrips() throws {
        let message = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "Ответ",
            direction: .outgoing,
            delivery: .sent,
            security: .omemo,
            replyToID: "original-id",
            replyToJID: "bob@example.org",
            replyPreview: "Исходный текст"
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.replyToID, "original-id")
        XCTAssertEqual(decoded.replyToJID, "bob@example.org")
        XCTAssertEqual(decoded.replyPreview, "Исходный текст")
    }

    func testRetractedMessageCannotBeEditedRepliedOrForwarded() {
        let message = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "Удалено",
            direction: .outgoing,
            delivery: .delivered,
            security: .omemo,
            retractedAt: Date()
        )

        XCTAssertFalse(message.canBeEdited)
        XCTAssertFalse(message.canBeRepliedTo)
        XCTAssertFalse(message.canBeForwarded)
        XCTAssertFalse(message.canBeRetracted)
        XCTAssertEqual(message.previewText, "🚫 Сообщение удалено")
    }

    func testLegacyMessageWithoutInteractionFieldsStillDecodes() throws {
        let original = ChatMessage(
            conversationID: "bob@example.org",
            senderJID: "alice@example.org",
            body: "Старый архив",
            direction: .incoming,
            delivery: .delivered,
            security: .omemo
        )
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in [
            "replyToID", "replyToJID", "replyPreview", "forwardedFrom", "retractedAt",
            "stanzaID", "senderDisplayName", "isGroupMessage", "callHistory"
        ] {
            object.removeValue(forKey: key)
        }

        let decoded = try JSONDecoder().decode(
            ChatMessage.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.replyToID)
        XCTAssertNil(decoded.retractedAt)
        XCTAssertEqual(decoded.body, "Старый архив")
        XCTAssertFalse(decoded.isGroupMessage)
    }

    func testGroupReplyRequiresRoomAssignedStanzaID() {
        var message = ChatMessage(
            conversationID: "team@conference.example.org",
            senderJID: "team@conference.example.org/alice",
            body: "Сообщение группы",
            direction: .incoming,
            delivery: .delivered,
            security: .omemo,
            senderDisplayName: "Alice",
            isGroupMessage: true
        )

        XCTAssertFalse(message.canBeRepliedTo)
        message.stanzaID = "room-stable-id"
        XCTAssertTrue(message.canBeRepliedTo)
        XCTAssertEqual(message.replyIdentifier, "room-stable-id")
        XCTAssertEqual(message.security, .omemo)
        XCTAssertFalse(message.canBeEdited)
        XCTAssertFalse(message.canBeRetracted)
    }

    func testCompletedVideoCallHistoryRoundTripsWithDuration() throws {
        let metadata = CallHistoryMetadata(isVideo: true, outcome: .completed)
        let message = ChatMessage(
            id: "call-alice-123",
            conversationID: "alice@example.org",
            senderJID: "me@example.org",
            body: "Видеозвонок",
            direction: .outgoing,
            delivery: .sent,
            security: .plaintext,
            kind: .system,
            duration: 65,
            callHistory: metadata
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.callHistory, metadata)
        XCTAssertEqual(decoded.callTitle, "Исходящий видеозвонок")
        XCTAssertEqual(decoded.callSubtitle, "Длительность 1:05")
        XCTAssertEqual(decoded.previewText, "🎥 Исходящий видеозвонок")
        XCTAssertFalse(decoded.canBeRepliedTo)
        XCTAssertFalse(decoded.canBeForwarded)
    }
}
