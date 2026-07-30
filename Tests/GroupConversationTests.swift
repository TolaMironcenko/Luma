import Foundation
import XCTest
@testable import Luma

final class GroupConversationTests: XCTestCase {
    func testGroupConversationRoundTrips() throws {
        let conversation = Conversation(
            jid: "team@conference.example.org",
            displayName: "Команда",
            encryptionPreference: .disabled,
            kind: .group,
            groupNickname: "Alice",
            isGroupJoined: true,
            shouldAutojoin: true,
            occupantCount: 4,
            invitedBy: "bob@example.org"
        )

        let decoded = try JSONDecoder().decode(
            Conversation.self,
            from: JSONEncoder().encode(conversation)
        )

        XCTAssertTrue(decoded.isGroup)
        XCTAssertEqual(decoded.groupNickname, "Alice")
        XCTAssertEqual(decoded.occupantCount, 4)
        XCTAssertEqual(decoded.invitedBy, "bob@example.org")
    }

    func testLegacyConversationDefaultsToDirect() throws {
        let conversation = Conversation(jid: "bob@example.org", displayName: "Bob")
        let encoded = try JSONEncoder().encode(conversation)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["kind", "groupNickname", "isGroupJoined", "shouldAutojoin", "occupantCount", "invitedBy"] {
            object.removeValue(forKey: key)
        }

        let decoded = try JSONDecoder().decode(
            Conversation.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(decoded.isGroup)
        XCTAssertFalse(decoded.isGroupJoined)
        XCTAssertEqual(decoded.occupantCount, 0)
    }

    func testNewGroupInheritsGlobalEncryptionByDefault() {
        let conversation = Conversation(
            jid: "team@conference.example.org",
            kind: .group
        )

        XCTAssertEqual(conversation.encryptionPreference, .inheritGlobal)
    }
}
