import XCTest
@testable import Luma

final class ArchiveSyncCheckpointTests: XCTestCase {
    func testStoredCursorIsPreferredOverTimestampOverlap() {
        let checkpoint = ArchiveSyncCheckpoint(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            cursor: " mam-42 "
        )

        let position = ArchiveSyncCursorPolicy.requestPosition(
            checkpoint: checkpoint,
            resumeAfter: nil,
            overlap: 60
        )

        XCTAssertEqual(position.after, "mam-42")
        XCTAssertNil(position.start)
    }

    func testLegacyTimestampUsesBoundedOverlap() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let position = ArchiveSyncCursorPolicy.requestPosition(
            checkpoint: ArchiveSyncCheckpoint(timestamp: timestamp),
            resumeAfter: nil,
            overlap: 60
        )

        XCTAssertNil(position.after)
        XCTAssertEqual(position.start, timestamp.addingTimeInterval(-60))
    }

    func testResumeCursorWinsOverDurableCursor() {
        let position = ArchiveSyncCursorPolicy.requestPosition(
            checkpoint: ArchiveSyncCheckpoint(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                cursor: "saved"
            ),
            resumeAfter: "page-in-flight",
            overlap: 60
        )

        XCTAssertEqual(position.after, "page-in-flight")
        XCTAssertNil(position.start)
    }

    func testCaughtUpCheckpointKeepsCursorAndAdvancesTimestamp() {
        let previous = ArchiveSyncCheckpoint(
            timestamp: Date(timeIntervalSince1970: 100),
            cursor: "known"
        )
        let queryStart = Date(timeIntervalSince1970: 200)

        let resolved = ArchiveSyncCursorPolicy.resolvedCheckpoint(
            previous: previous,
            cursor: nil,
            highWatermark: nil,
            queryStartedAt: queryStart,
            caughtUp: true
        )

        XCTAssertEqual(resolved.cursor, "known")
        XCTAssertEqual(resolved.timestamp, queryStart)
    }

    func testSameTimestampStillAdvancesWhenCursorChanges() {
        let previous = ArchiveSyncCheckpoint(
            timestamp: Date(timeIntervalSince1970: 100),
            cursor: "old"
        )
        let resolved = ArchiveSyncCursorPolicy.resolvedCheckpoint(
            previous: previous,
            cursor: "new",
            highWatermark: previous.timestamp,
            queryStartedAt: Date(timeIntervalSince1970: 200),
            caughtUp: false
        )

        XCTAssertTrue(resolved.advances(over: previous))
        XCTAssertEqual(resolved.cursor, "new")
    }

    func testStoredCursorFallbackCanRunOnlyOnFirstPageAndOnlyOnce() {
        let checkpoint = ArchiveSyncCheckpoint(
            timestamp: Date(timeIntervalSince1970: 100),
            cursor: "stored"
        )

        XCTAssertTrue(ArchiveSyncCursorPolicy.shouldFallbackFromStoredCursor(
            requestedAfter: "stored",
            checkpoint: checkpoint,
            hasCompletedPage: false,
            fallbackAlreadyUsed: false
        ))
        XCTAssertFalse(ArchiveSyncCursorPolicy.shouldFallbackFromStoredCursor(
            requestedAfter: "stored",
            checkpoint: checkpoint,
            hasCompletedPage: true,
            fallbackAlreadyUsed: false
        ))
        XCTAssertFalse(ArchiveSyncCursorPolicy.shouldFallbackFromStoredCursor(
            requestedAfter: "stored",
            checkpoint: checkpoint,
            hasCompletedPage: false,
            fallbackAlreadyUsed: true
        ))
    }
}
