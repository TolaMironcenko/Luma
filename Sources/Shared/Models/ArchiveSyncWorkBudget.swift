import Foundation

/// Limits one foreground MAM pass. A large archive is advanced over several
/// app activations instead of monopolizing the main actor indefinitely.
struct ArchiveSyncWorkBudget: Equatable, Sendable {
    static let maximumCompletedPages = 2
    static let maximumRuntime: TimeInterval = 2

    private(set) var completedPages = 0
    let startedAt: Date

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    mutating func recordCompletedPage(at date: Date = Date()) -> Bool {
        completedPages += 1
        return completedPages >= Self.maximumCompletedPages
            || date.timeIntervalSince(startedAt) >= Self.maximumRuntime
    }
}
