import Foundation

/// Bounds whole-query MAM recovery so a server that keeps returning the same
/// broken page cannot leave the client in an endless restart loop.
enum ArchiveSyncRecoveryPolicy {
    static let incrementalOverlap: TimeInterval = 60
    static let interPageDelayNanoseconds: UInt64 = 100_000_000
    static let queryTimeoutNanoseconds: UInt64 = 12_000_000_000
    static let pageApplyTimeoutNanoseconds: UInt64 = 8_000_000_000
    static let pageRetryLimit = 1
    static let resumeAfterCaptureDelayNanoseconds: UInt64 = 3_000_000_000
}
