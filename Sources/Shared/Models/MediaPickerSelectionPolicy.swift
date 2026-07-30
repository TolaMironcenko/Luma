enum MediaPickerRepresentation: Equatable, Sendable {
    case photo
    case video
}

enum MediaPickerSelectionPolicy {
    static func preferredOrder(
        supportsImage: Bool,
        supportsVideo: Bool
    ) -> [MediaPickerRepresentation] {
        // Live Photos can expose both types. Their still image is the most
        // predictable cross-client representation; a video-only asset keeps
        // movie first. The second entry is an explicit provider fallback.
        supportsVideo && !supportsImage
            ? [.video, .photo]
            : [.photo, .video]
    }
}
