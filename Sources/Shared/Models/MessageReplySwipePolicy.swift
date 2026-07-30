import CoreGraphics

struct MessageReplySwipePolicy {
    static let triggerDistance: CGFloat = 64
    static let maximumOffset: CGFloat = 76
    static let horizontalDominance: CGFloat = 1.4

    static func offset(for translation: CGSize) -> CGFloat {
        guard isHorizontal(translation) else { return 0 }
        let distance = min(abs(translation.width) * 0.72, maximumOffset)
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
