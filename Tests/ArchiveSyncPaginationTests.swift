import XCTest
@testable import Luma

final class ArchiveSyncPaginationTests: XCTestCase {
    func testCompleteResponseFinishesEvenWhenCursorExists() {
        var pagination = ArchiveSyncPagination()

        XCTAssertEqual(
            pagination.decision(
                complete: true,
                lastCursor: "server-last",
                requestedAfter: nil
            ),
            .finished
        )
    }

    func testIncompleteResponseContinuesWithNewCursor() {
        var pagination = ArchiveSyncPagination()

        XCTAssertEqual(
            pagination.decision(
                complete: false,
                lastCursor: "page-1-last",
                requestedAfter: nil
            ),
            .next("page-1-last")
        )
    }

    func testRepeatedCursorStopsPaginationLoop() {
        var pagination = ArchiveSyncPagination()
        _ = pagination.decision(
            complete: false,
            lastCursor: "repeated",
            requestedAfter: nil
        )

        XCTAssertEqual(
            pagination.decision(
                complete: false,
                lastCursor: "repeated",
                requestedAfter: "repeated"
            ),
            .invalidCursor
        )
    }

    func testCursorCycleStopsPaginationLoop() {
        var pagination = ArchiveSyncPagination()
        XCTAssertEqual(
            pagination.decision(
                complete: false,
                lastCursor: "page-a",
                requestedAfter: nil
            ),
            .next("page-a")
        )
        XCTAssertEqual(
            pagination.decision(
                complete: false,
                lastCursor: "page-b",
                requestedAfter: "page-a"
            ),
            .next("page-b")
        )

        XCTAssertEqual(
            pagination.decision(
                complete: false,
                lastCursor: "page-a",
                requestedAfter: "page-b"
            ),
            .invalidCursor
        )
    }

    func testIncompleteResponseWithoutCursorDoesNotAdvanceCheckpoint() {
        var pagination = ArchiveSyncPagination()

        XCTAssertEqual(
            pagination.decision(
                complete: false,
                lastCursor: nil,
                requestedAfter: nil
            ),
            .invalidCursor
        )
    }
}
