import CoreGraphics

struct MessageReplySwipePolicy {
    static let triggerDistance: CGFloat = 64
    /// Horizontal travel required before the reply indicator appears. Keeps
    /// the per-cell state untouched during ordinary vertical scrolling.
    static let activationDistance: CGFloat = 24
    static let maximumOffset: CGFloat = 76
    /// The drag must be clearly horizontal: a mostly vertical timeline scroll
    /// (even a diagonal one) must never arm the reply swipe or move bubbles.
    static let horizontalDominance: CGFloat = 2.0

    static func offset(for translation: CGSize) -> CGFloat {
        guard isHorizontal(translation) else { return 0 }
        let width = abs(translation.width)
        guard width >= activationDistance else { return 0 }
        let distance = min((width - activationDistance) * 0.72 + 12, maximumOffset)
        return translation.width < 0 ? -distance : distance
    }

    static func shouldReply(
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        let candidate = abs(predictedEndTranslation.width) > abs(translation.width)
            ? predictedEndTranslation
            : translation
        return isHorizontal(candidate) && abs(candidate.width) >= triggerDistance
    }

    static func progress(for offset: CGFloat) -> CGFloat {
        min(1, abs(offset) / triggerDistance)
    }

    private static func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * horizontalDominance
    }
}
