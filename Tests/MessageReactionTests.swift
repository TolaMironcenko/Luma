import XCTest
@testable import Luma

final class MessageReactionTests: XCTestCase {
    func testReactionUpdateKeepsOneCopyOfEachEmoji() {
        XCTAssertEqual(
            MessageReactionPolicy.sanitized(["👍", " 👍 ", "❤️", "a", "not emoji"]),
            ["👍", "❤️"]
        )
    }

    func testSummariesCountSendersAndMarkOwnReaction() {
        let reactions = [
            MessageReaction(senderJID: "me@example.org/device", emojis: ["👍", "❤️"]),
            MessageReaction(senderJID: "you@example.org", emojis: ["👍"])
        ]
        let summaries = MessageReactionPolicy.summaries(
            reactions: reactions,
            ownJID: "me@example.org"
        )
        XCTAssertEqual(
            summaries.first(where: { $0.emoji == "👍" }),
            MessageReactionSummary(emoji: "👍", count: 2, includesOwnReaction: true)
        )
        XCTAssertEqual(
            summaries.first(where: { $0.emoji == "❤️" }),
            MessageReactionSummary(emoji: "❤️", count: 1, includesOwnReaction: true)
        )
    }

    func testOlderArchivesDecodeWithoutReactionField() throws {
        let message = ChatMessage(
            conversationID: "peer@example.org",
            senderJID: "peer@example.org",
            body: "hello",
            direction: .incoming,
            delivery: .delivered,
            security: .plaintext
        )
        let encoded = try JSONEncoder().encode(message)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "reactions")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(ChatMessage.self, from: legacyData).reactions, [])
    }
}
