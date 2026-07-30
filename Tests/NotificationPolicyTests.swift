import XCTest
@testable import Luma

final class NotificationPolicyTests: XCTestCase {
    func testForegroundMessageFromAnotherConversationIsPresented() {
        XCTAssertTrue(NotificationPolicy.shouldPresentMessage(
            inserted: true,
            isOutgoing: false,
            appIsActive: true,
            selectedConversationID: "bob@example.org",
            conversationID: "alice@example.org"
        ))
    }

    func testVisibleConversationDoesNotPresentDuplicateBanner() {
        XCTAssertFalse(NotificationPolicy.shouldPresentMessage(
            inserted: true,
            isOutgoing: false,
            appIsActive: true,
            selectedConversationID: "alice@example.org",
            conversationID: "ALICE@example.org"
        ))
    }

    func testBackgroundIncomingMessageIsPresented() {
        XCTAssertTrue(NotificationPolicy.shouldPresentMessage(
            inserted: true,
            isOutgoing: false,
            appIsActive: false,
            selectedConversationID: "alice@example.org",
            conversationID: "alice@example.org"
        ))
    }

    func testOutgoingOrDuplicateMessageIsNotPresented() {
        XCTAssertFalse(NotificationPolicy.shouldPresentMessage(
            inserted: true,
            isOutgoing: true,
            appIsActive: true,
            selectedConversationID: nil,
            conversationID: "alice@example.org"
        ))
        XCTAssertFalse(NotificationPolicy.shouldPresentMessage(
            inserted: false,
            isOutgoing: false,
            appIsActive: true,
            selectedConversationID: nil,
            conversationID: "alice@example.org"
        ))
    }
}
