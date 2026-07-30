import Foundation

/// A cached presentation row for the selected chat. Building day boundaries
/// once per message mutation avoids walking the full history during every
/// scroll-position or composer-state update.
struct ChatTimelineEntry: Identifiable, Hashable, Sendable {
    let message: ChatMessage
    let startsNewDay: Bool

    var id: String { message.id }

    static func make(
        from messages: [ChatMessage],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ChatTimelineEntry] {
        var previousTimestamp: Date?
        return messages.map { message in
            let startsNewDay = previousTimestamp.map {
                !calendar.isDate($0, inSameDayAs: message.timestamp)
            } ?? true
            previousTimestamp = message.timestamp
            return ChatTimelineEntry(
                message: message,
                startsNewDay: startsNewDay
            )
        }
    }
}
