import XCTest
@testable import Luma

final class ChatArchiveTests: XCTestCase {
    func testSnapshotRoundTrip() async throws {
        let jid = "test-\(UUID().uuidString)@example.org"
        let archive = ChatArchive(accountJID: jid)
        let conversation = Conversation(jid: "bob@example.org", displayName: "Bob")
        let message = ChatMessage(
            conversationID: conversation.id,
            senderJID: jid,
            body: "Encrypted hello",
            direction: .outgoing,
            delivery: .sent,
            security: .omemo
        )

        try await archive.save(.init(
            conversations: [conversation],
            messages: [message],
            locallyDeletedMessageIDs: ["deleted-message-id"],
            rosterContactJIDs: [conversation.jid],
            lastSuccessfulMAMSync: Date(timeIntervalSince1970: 1_700_000_000),
            lastSuccessfulMAMCursor: "mam-cursor-42"
        ))
        let loaded = await archive.load()

        XCTAssertEqual(loaded.conversations, [conversation])
        XCTAssertEqual(loaded.messages, [message])
        XCTAssertEqual(loaded.locallyDeletedMessageIDs, Set(["deleted-message-id"]))
        XCTAssertEqual(loaded.rosterContactJIDs, Set([conversation.jid]))
        XCTAssertEqual(
            loaded.lastSuccessfulMAMSync,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(loaded.lastSuccessfulMAMCursor, "mam-cursor-42")
        XCTAssertEqual(loaded.schemaVersion, ChatArchive.Snapshot.currentSchemaVersion)
        try await archive.erase()
    }

    func testLegacySnapshotDefaultsToSchemaOne() throws {
        let data = Data(
            #"{"conversations":[],"messages":[],"locallyDeletedMessageIDs":[]}"#.utf8
        )

        let snapshot = try JSONDecoder().decode(ChatArchive.Snapshot.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertTrue(snapshot.rosterContactJIDs.isEmpty)
        XCTAssertNil(snapshot.lastSuccessfulMAMSync)
        XCTAssertNil(snapshot.lastSuccessfulMAMCursor)
    }
}
