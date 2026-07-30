import Foundation
import UniformTypeIdentifiers

enum MediaMetadata {
    struct Inferred: Equatable, Sendable {
        let kind: ChatMessage.Kind
        let mimeType: String?
        let duration: TimeInterval?
    }

    static func transportFilename(
        originalFilename: String,
        kind: ChatMessage.Kind,
        duration: TimeInterval?
    ) -> String {
        let milliseconds = duration.flatMap { value -> Int? in
            guard value.isFinite,
                  value > 0,
                  value <= Double(Int.max) / 1_000 else { return nil }
            return Int((value * 1_000).rounded())
        }
        guard let milliseconds else { return originalFilename }

        switch kind {
        case .voice:
            return "luma-voice-\(milliseconds)-\(originalFilename)"
        case .videoNote:
            return "luma-videonote-\(milliseconds)-\(originalFilename)"
        default:
            return originalFilename
        }
    }

    static func infer(from transportFilename: String) -> Inferred {
        let contentType = UTType(
            filenameExtension: URL(fileURLWithPath: transportFilename).pathExtension
        )
        let kind: ChatMessage.Kind
        if transportFilename.hasPrefix("luma-voice-") {
            kind = .voice
        } else if transportFilename.hasPrefix("luma-videonote-") {
            kind = .videoNote
        } else if contentType?.conforms(to: .image) == true {
            kind = .photo
        } else if contentType?.conforms(to: .movie) == true {
            kind = .video
        } else if contentType?.conforms(to: .audio) == true {
            kind = .audio
        } else {
            kind = .attachment
        }

        return Inferred(
            kind: kind,
            mimeType: contentType?.preferredMIMEType,
            duration: encodedDuration(from: transportFilename)
        )
    }

    private static func encodedDuration(from filename: String) -> TimeInterval? {
        let prefix: String
        if filename.hasPrefix("luma-voice-") {
            prefix = "luma-voice-"
        } else if filename.hasPrefix("luma-videonote-") {
            prefix = "luma-videonote-"
        } else {
            return nil
        }

        let remainder = filename.dropFirst(prefix.count)
        guard let separator = remainder.firstIndex(of: "-"),
              let milliseconds = Int(remainder[..<separator]),
              milliseconds > 0 else { return nil }
        return TimeInterval(milliseconds) / 1_000
    }
}
