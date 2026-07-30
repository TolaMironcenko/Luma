import Foundation

enum VideoNoteRecordingLifecycle: Equatable, Sendable {
    case idle
    case prepared
    case starting
    case recording
    case stopping

    var isBusy: Bool {
        switch self {
        case .starting, .recording, .stopping:
            return true
        case .idle, .prepared:
            return false
        }
    }

    static func acceptsCompletion(activeURL: URL?, outputURL: URL) -> Bool {
        guard let activeURL else { return false }
        return normalizedRecordingPath(activeURL) == normalizedRecordingPath(outputURL)
    }

    /// AVFoundation can return a temporary file through its canonical macOS
    /// path (`/private/var/...`) even when the caller supplied the equivalent
    /// user-facing path (`/var/...`). Treat those aliases as one recording so
    /// a valid delegate callback is not mistaken for a stale attempt.
    private static func normalizedRecordingPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        for privateAlias in ["/private/var", "/private/tmp"] {
            if path == privateAlias || path.hasPrefix(privateAlias + "/") {
                path.removeFirst("/private".count)
                break
            }
        }
        return path
    }
}
