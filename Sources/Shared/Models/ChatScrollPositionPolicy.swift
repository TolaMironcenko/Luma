import CoreGraphics

enum ChatScrollPositionPolicy {
    static let nearBottomThreshold: CGFloat = 96

    static func isNearBottom(
        bottomY: CGFloat,
        viewportHeight: CGFloat
    ) -> Bool {
        guard bottomY.isFinite, viewportHeight.isFinite, viewportHeight > 0 else {
            return true
        }
        return bottomY <= viewportHeight + nearBottomThreshold
    }

    static func isNearBottom(distanceFromBottom: CGFloat) -> Bool {
        guard distanceFromBottom.isFinite else { return true }
        return distanceFromBottom <= nearBottomThreshold
    }
}
