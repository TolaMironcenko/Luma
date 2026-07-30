import Foundation

/// Keeps MAM work below a visible frame-sized burst. A whole decoded pass is
/// still published atomically; these values only bound network and decryption
/// work performed before that publication.
enum ArchiveMessageBatchPolicy {
    static let pageSize = 24
    static let bootstrapMessageLimit = 40
    static let decodeSliceSize = 1
    static let maximumBufferedStanzas = 48
    /// Leave roughly half of a 60 Hz frame between archived decryptions. This
    /// keeps UIScrollView touch handling responsive even when OMEMO work is
    /// unusually expensive on older devices.
    static let interSliceDelayNanoseconds: UInt64 = 8_000_000
}
