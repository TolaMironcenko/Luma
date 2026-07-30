import Foundation

/// Builds and removes the plain-text quote used when a peer does not render
/// XEP-0461 replies. XEP-0428 offsets are Unicode scalar offsets, not UTF-16.
enum MessageReplyFallback {
    struct Parsed: Equatable, Sendable {
        let body: String
        let preview: String?
    }

    static func make(author: String, preview: String) -> (prefix: String, scalarCount: Int) {
        let safeAuthor = author
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteLines = preview
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(8)
            .map { "> \($0)" }
        let prefix = (["> \(safeAuthor) написал(а):"] + quoteLines).joined(separator: "\n") + "\n\n"
        return (prefix, prefix.unicodeScalars.count)
    }

    static func parse(
        body: String,
        fallbackStart: Int?,
        fallbackEnd: Int?
    ) -> Parsed {
        if let fallbackStart,
           let fallbackEnd,
           let fallback = scalarSubstring(body, start: fallbackStart, end: fallbackEnd),
           let stripped = removingScalarRange(body, start: fallbackStart, end: fallbackEnd) {
            return Parsed(
                body: stripped.trimmingCharacters(in: .whitespacesAndNewlines),
                preview: quotePreview(from: fallback)
            )
        }
        return parseLegacyQuote(body) ?? Parsed(body: body, preview: nil)
    }

    static func parseLegacyQuote(_ body: String) -> Parsed? {
        let lines = body.components(separatedBy: .newlines)
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces).hasPrefix(">") else { return nil }

        var quoteLines: [String] = []
        var bodyStart = 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                bodyStart = index + 1
                continue
            }
            if trimmed.isEmpty, !quoteLines.isEmpty {
                bodyStart = index + 1
                continue
            }
            break
        }

        guard !quoteLines.isEmpty, bodyStart < lines.count else { return nil }
        let remaining = lines[bodyStart...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remaining.isEmpty else { return nil }
        return Parsed(body: remaining, preview: normalizedPreview(quoteLines))
    }

    private static func quotePreview(from fallback: String) -> String? {
        let lines = fallback.components(separatedBy: .newlines).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { return nil }
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return normalizedPreview(lines)
    }

    private static func normalizedPreview(_ lines: [String]) -> String? {
        var values = lines.filter { !$0.isEmpty }
        if values.count > 1,
           let first = values.first?.lowercased(),
           first.hasSuffix(":") || first.contains(" wrote") || first.contains("написал") {
            values.removeFirst()
        }
        let value = values.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value.count > 280 ? String(value.prefix(277)) + "…" : value
    }

    private static func scalarSubstring(_ value: String, start: Int, end: Int) -> String? {
        let scalars = value.unicodeScalars
        guard start >= 0, end >= start, end <= scalars.count else { return nil }
        let lower = scalars.index(scalars.startIndex, offsetBy: start)
        let upper = scalars.index(scalars.startIndex, offsetBy: end)
        return String(value[lower..<upper])
    }

    private static func removingScalarRange(_ value: String, start: Int, end: Int) -> String? {
        let scalars = value.unicodeScalars
        guard start >= 0, end >= start, end <= scalars.count else { return nil }
        let lower = scalars.index(scalars.startIndex, offsetBy: start)
        let upper = scalars.index(scalars.startIndex, offsetBy: end)
        return String(value[..<lower]) + String(value[upper...])
    }
}
