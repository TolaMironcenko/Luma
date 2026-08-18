import SwiftData
import XCTest
@testable import Luma

@MainActor
final class ArchiveStoreTests: XCTestCase {
    func testStoreRoundTrip() async throws {
        let jid = "test-\(UUID().uuidString)@example.org"
        let store = try ArchiveStore(accountJID: jid)
        defer { try? store.erase() }

        let conversation = Conversation(jid: "bob@example.org", displayName: "Bob")
        let message = ChatMessage(
            conversationID: conversation.jid,
            senderJID: jid,
            body: "Encrypted hello",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            direction: .outgoing,
            delivery: .sent,
            security: .omemo
        )
        store.context.insert(conversation)
        store.context.insert(message)

        try store.save(
            locallyDeletedMessageIDs: ["deleted-message-id"],
            rosterContactJIDs: [conversation.jid],
            lastSuccessfulMAMSync: Date(timeIntervalSince1970: 1_700_000_000),
            lastSuccessfulMAMCursor: "mam-cursor-42",
            mamCheckpoints: [:]
        )

        let loaded = store.load()
        XCTAssertEqual(loaded.conversations.map(\.jid), [conversation.jid])
        XCTAssertEqual(loaded.messages.map(\.clientID), [message.clientID])
        XCTAssertEqual(loaded.locallyDeletedMessageIDs, Set(["deleted-message-id"]))
        XCTAssertEqual(loaded.rosterContactJIDs, Set([conversation.jid]))
        XCTAssertEqual(
            loaded.lastSuccessfulMAMSync,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(loaded.lastSuccessfulMAMCursor, "mam-cursor-42")
    }

    func testLegacyImportMapsConversationAndMessage() throws {
        let jid = "test-\(UUID().uuidString)@example.org"
        let legacy = LegacyArchiveImporter.Snapshot(
            schemaVersion: 1,
            conversations: [
                LegacyArchiveImporter.LegacyConversation(
                    id: "bob@example.org",
                    jid: "bob@example.org",
                    displayName: "Bob",
                    lastMessage: "",
                    lastActivity: .distantPast,
                    unreadCount: 0,
                    isOnline: false,
                    isPinned: false,
                    encryptionPreference: .inheritGlobal,
                    kind: .direct,
                    groupNickname: nil,
                    isGroupJoined: false,
                    shouldAutojoin: false,
                    occupantCount: 0,
                    invitedBy: nil
                )
            ],
            messages: [
                LegacyArchiveImporter.LegacyMessage(
                    id: "msg-1",
                    conversationID: "bob@example.org",
                    senderJID: jid,
                    body: "Hello",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    direction: .outgoing,
                    delivery: .sent,
                    security: .omemo,
                    kind: .text,
                    remoteAttachmentURL: nil,
                    localFilename: nil,
                    mimeType: nil,
                    duration: nil,
                    byteCount: nil,
                    encryptionFingerprint: nil,
                    editedAt: nil,
                    replyToID: nil,
                    replyToJID: nil,
                    replyPreview: nil,
                    forwardedFrom: nil,
                    retractedAt: nil,
                    originID: nil,
                    stanzaID: nil,
                    senderDisplayName: nil,
                    isGroupMessage: false,
                    callHistory: nil,
                    reactions: []
                )
            ],
            locallyDeletedMessageIDs: [],
            rosterContactJIDs: [],
            lastSuccessfulMAMSync: nil,
            lastSuccessfulMAMCursor: nil,
            mamCheckpoints: [:]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(legacy)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)

        let imported = try LegacyArchiveImporter.importIfNeeded(from: url)
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.conversations.map(\.jid), ["bob@example.org"])
        XCTAssertEqual(imported?.messages.map(\.clientID), ["msg-1"])
        XCTAssertEqual(imported?.messages.first?.conversation?.jid, "bob@example.org")
    }
}
