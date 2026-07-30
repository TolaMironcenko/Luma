import XCTest
@testable import Luma

final class ChatTimelineEntryTests: XCTestCase {
    func testDayBoundariesArePrecomputedOnceForStableRows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = ChatMessage(
            id: "first",
            conversationID: "friend@example.org",
            senderJID: "friend@example.org",
            body: "one",
            timestamp: Date(timeIntervalSince1970: 1_704_067_200),
            direction: .incoming,
            delivery: .delivered,
            security: .plaintext
        )
        var sameDay = first
        sameDay.body = "two"
        sameDay.timestamp = first.timestamp.addingTimeInterval(60)
        let sameDayMessage = ChatMessage(
            id: "same-day",
            conversationID: sameDay.conversationID,
            senderJID: sameDay.senderJID,
            body: sameDay.body,
            timestamp: sameDay.timestamp,
            direction: sameDay.direction,
            delivery: sameDay.delivery,
            security: sameDay.security
        )
        let nextDay = ChatMessage(
            id: "next-day",
            conversationID: first.conversationID,
            senderJID: first.senderJID,
            body: "three",
            timestamp: first.timestamp.addingTimeInterval(86_400),
            direction: .incoming,
            delivery: .delivered,
            security: .plaintext
        )

        let entries = ChatTimelineEntry.make(
            from: [first, sameDayMessage, nextDay],
            calendar: calendar
        )

        XCTAssertEqual(entries.map(\.id), ["first", "same-day", "next-day"])
        XCTAssertEqual(entries.map(\.startsNewDay), [true, false, true])
    }
}
