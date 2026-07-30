import Foundation

/// Tracks overlapping media operations without letting an older operation
/// restore a stale busy state after a newer one has already finished.
struct MediaSendActivityTracker: Sendable {
    private(set) var activeTokens: Set<UUID> = []

    var isActive: Bool {
        !activeTokens.isEmpty
    }

    mutating func begin() -> UUID {
        let token = UUID()
        activeTokens.insert(token)
        return token
    }

    mutating func end(_ token: UUID) {
        activeTokens.remove(token)
    }

    mutating func reset() {
        activeTokens.removeAll()
    }
}
