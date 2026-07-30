import XCTest
@testable import Luma

final class ChatTypingPolicyTests: XCTestCase {
    func testDirectChatUsesCompactTypingText() {
        XCTAssertEqual(
            ChatTypingPolicy.displayText(names: ["Alice"], isGroup: false),
            "печатает…"
        )
    }

    func testGroupChatNamesOneOrTwoParticipants() {
        XCTAssertEqual(
            ChatTypingPolicy.displayText(names: ["Alice"], isGroup: true),
            "Alice печатает…"
        )
        XCTAssertEqual(
            ChatTypingPolicy.displayText(names: ["Bob", "Alice"], isGroup: true),
            "Alice и Bob печатают…"
        )
    }

    func testEmptyTypingSetHasNoIndicator() {
        XCTAssertNil(ChatTypingPolicy.displayText(names: [], isGroup: false))
    }
}
