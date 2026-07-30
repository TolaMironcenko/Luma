import Foundation

enum ArchiveSyncPageDecision: Equatable, Sendable {
    case finished
    case next(String)
    case invalidCursor
}

/// Validates XEP-0313/RSM cursors so a misbehaving server cannot leave
/// history synchronization spinning forever on the same page.
struct ArchiveSyncPagination: Sendable {
    private(set) var seenCursors: Set<String> = []

    mutating func decision(
        complete: Bool,
        lastCursor: String?,
        requestedAfter: String?
    ) -> ArchiveSyncPageDecision {
        if complete { return .finished }
        guard let cursor = lastCursor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cursor.isEmpty else {
            // An incomplete response without an RSM cursor cannot prove that
            // the archive is exhausted. Advancing the checkpoint here would
            // silently skip the remaining history.
            return .invalidCursor
        }
        guard cursor != requestedAfter,
              seenCursors.insert(cursor).inserted else {
            return .invalidCursor
        }
        return .next(cursor)
    }
}
