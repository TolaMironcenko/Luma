import Foundation

enum ChatTypingState: String, Sendable {
    case active
    case composing
    case paused
    case inactive
    case gone
}

enum ChatTypingPolicy {
    static let pauseDelayNanoseconds: UInt64 = 5_000_000_000
    static let remoteExpiryNanoseconds: UInt64 = 8_000_000_000

    static func displayText(names: [String], isGroup: Bool) -> String? {
        let uniqueNames = Array(Set(names.filter { !$0.isEmpty })).sorted()
        guard !uniqueNames.isEmpty else { return nil }
        guard isGroup else { return "печатает…" }

        switch uniqueNames.count {
        case 1:
            return "\(uniqueNames[0]) печатает…"
        case 2:
            return "\(uniqueNames[0]) и \(uniqueNames[1]) печатают…"
        default:
            return "Несколько участников печатают…"
        }
    }
}
