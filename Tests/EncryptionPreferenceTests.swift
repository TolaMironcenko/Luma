import Foundation
import XCTest
@testable import Luma

final class EncryptionPreferenceTests: XCTestCase {
    func testResolutionUsesGlobalDefaultAndPerChatOverride() {
        XCTAssertTrue(EncryptionPreference.inheritGlobal.resolved(globalEnabled: true))
        XCTAssertFalse(EncryptionPreference.inheritGlobal.resolved(globalEnabled: false))
        XCTAssertTrue(EncryptionPreference.enabled.resolved(globalEnabled: false))
        XCTAssertFalse(EncryptionPreference.disabled.resolved(globalEnabled: true))
    }

    func testConversationWithoutEncryptionFieldStillDecodes() throws {
        let conversation = Conversation(jid: "bob@example.org", displayName: "Bob")
        let encoded = try JSONEncoder().encode(conversation)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "encryptionPreference")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Conversation.self, from: legacyData)

        XCTAssertEqual(decoded.encryptionPreference, .inheritGlobal)
        XCTAssertEqual(decoded.jid, conversation.jid)
    }

    func testGlobalSettingIsStoredPerAccount() throws {
        let suite = "LumaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AccountPreferences(defaults: defaults)

        XCTAssertTrue(preferences.encryptionEnabled(for: "alice@example.org"))
        preferences.setEncryptionEnabled(false, for: "alice@example.org")

        XCTAssertFalse(preferences.encryptionEnabled(for: "alice@example.org"))
        XCTAssertTrue(preferences.encryptionEnabled(for: "bob@example.org"))
    }
}
