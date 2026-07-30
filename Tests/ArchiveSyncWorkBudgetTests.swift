import XCTest
@testable import Luma

final class ArchiveSyncWorkBudgetTests: XCTestCase {
    func testStopsAfterFinitePageBudget() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var budget = ArchiveSyncWorkBudget(startedAt: start)

        for page in 1..<ArchiveSyncWorkBudget.maximumCompletedPages {
            XCTAssertFalse(
                budget.recordCompletedPage(at: start.addingTimeInterval(Double(page)))
            )
        }
        XCTAssertTrue(budget.recordCompletedPage(at: start.addingTimeInterval(6)))
    }

    func testStopsAfterRuntimeBudgetEvenWithFewPages() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var budget = ArchiveSyncWorkBudget(startedAt: start)

        XCTAssertTrue(budget.recordCompletedPage(
            at: start.addingTimeInterval(ArchiveSyncWorkBudget.maximumRuntime)
        ))
    }
}
