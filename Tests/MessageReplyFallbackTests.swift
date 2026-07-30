import XCTest
@testable import Luma

final class MessageReplyFallbackTests: XCTestCase {
    func testXEP0428ScalarRangeRemovesUnicodeQuote() {
        let fallback = MessageReplyFallback.make(
            author: "алиса@example.org",
            preview: "Привет 👋\nКак дела?"
        )
        let body = fallback.prefix + "Отлично!"

        let parsed = MessageReplyFallback.parse(
            body: body,
            fallbackStart: 0,
            fallbackEnd: fallback.scalarCount
        )

        XCTAssertEqual(parsed.body, "Отлично!")
        XCTAssertEqual(parsed.preview, "Привет 👋\nКак дела?")
        XCTAssertEqual(fallback.scalarCount, fallback.prefix.unicodeScalars.count)
    }

    func testLegacyConversationsQuoteBecomesReplyPreview() {
        let parsed = MessageReplyFallback.parse(
            body: "> Старое сообщение\n> в двух строках\n\nНовый ответ",
            fallbackStart: nil,
            fallbackEnd: nil
        )

        XCTAssertEqual(parsed.body, "Новый ответ")
        XCTAssertEqual(parsed.preview, "Старое сообщение\nв двух строках")
    }

    func testPlainBodyWithoutQuoteIsUnchanged() {
        let body = "Обычное сообщение"
        let parsed = MessageReplyFallback.parse(
            body: body,
            fallbackStart: nil,
            fallbackEnd: nil
        )

        XCTAssertEqual(parsed.body, body)
        XCTAssertNil(parsed.preview)
    }
}
