import Foundation
import UniformTypeIdentifiers

struct LoadedMediaFile: Sendable {
    let data: Data
    let filename: String
    let mimeType: String
    let inferredKind: ChatMessage.Kind
}

struct StagedMediaFile: Sendable {
    let url: URL
    let filename: String
    let contentTypeIdentifier: String?
    let byteCount: Int
}

enum MediaFileIOError: LocalizedError, Sendable {
    case coordinatedReadFailed(String)
    case emptyFile(String)
    case unreadableFile(String)

    var errorDescription: String? {
        switch self {
        case .coordinatedReadFailed(let message):
            return "Не удалось получить выбранный файл: \(message)"
        case .emptyFile(let filename):
            return "Файл «\(filename)» пуст или ещё не загружен из iCloud."
        case .unreadableFile(let filename):
            return "Не удалось подготовить «\(filename)» для отправки."
        }
    }
}

/// Serializes potentially large media file reads and writes away from the
/// main actor so finishing a video note cannot freeze the composer.
actor MediaFileIO {
    /// Monal immediately copies an item-provider URL into its own cache under
    /// NSFileCoordinator before preview or upload work starts. Do the same for
    /// every Luma draft so Photos/iCloud temporary URLs can disappear safely.
    func stageAttachmentDraft(from source: URL) throws -> StagedMediaFile {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("LumaAttachmentDrafts", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
        }

        var coordinatedError: NSError?
        var stagedResult: Result<StagedMediaFile, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            readingItemAt: source,
            options: [],
            error: &coordinatedError
        ) { coordinatedURL in
            stagedResult = Result {
                let originalValues = try? source.resourceValues(
                    forKeys: [.nameKey, .contentTypeKey]
                )
                let coordinatedValues = try coordinatedURL.resourceValues(
                    forKeys: [.fileSizeKey, .contentTypeKey]
                )
                let sourceName = originalValues?.name ?? source.lastPathComponent
                let filename = sourceName.isEmpty
                    ? coordinatedURL.lastPathComponent
                    : sourceName
                let safeComponent = Self.safePathComponent(filename)
                let destination = directory.appendingPathComponent(
                    "\(UUID().uuidString)-\(safeComponent)"
                )

                do {
                    try fileManager.copyItem(at: coordinatedURL, to: destination)
                    let stagedValues = try destination.resourceValues(
                        forKeys: [.fileSizeKey, .isRegularFileKey]
                    )
                    let byteCount = stagedValues.fileSize ?? coordinatedValues.fileSize ?? 0
                    guard stagedValues.isRegularFile == true,
                          fileManager.isReadableFile(atPath: destination.path) else {
                        throw MediaFileIOError.unreadableFile(filename)
                    }
                    guard byteCount > 0 else {
                        throw MediaFileIOError.emptyFile(filename)
                    }
                    let contentType = originalValues?.contentType
                        ?? coordinatedValues.contentType
                        ?? UTType(filenameExtension: source.pathExtension)
                    return StagedMediaFile(
                        url: destination,
                        filename: filename,
                        contentTypeIdentifier: contentType?.identifier,
                        byteCount: byteCount
                    )
                } catch {
                    try? fileManager.removeItem(at: destination)
                    throw error
                }
            }
        }

        if let stagedResult {
            return try stagedResult.get()
        }
        throw MediaFileIOError.coordinatedReadFailed(
            coordinatedError?.localizedDescription ?? "неизвестная ошибка"
        )
    }

    func load(
        from url: URL,
        preferredKind: ChatMessage.Kind?
    ) throws -> LoadedMediaFile {
        let values = try url.resourceValues(forKeys: [.nameKey, .contentTypeKey])
        let filename = values.name ?? url.lastPathComponent
        let contentType = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        let kind = preferredKind ?? Self.mediaKind(
            for: contentType,
            filename: filename
        )
        return LoadedMediaFile(
            data: try Data(contentsOf: url, options: [.mappedIfSafe]),
            filename: filename,
            mimeType: contentType?.preferredMIMEType ?? "application/octet-stream",
            inferredKind: kind
        )
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    private static func safePathComponent(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:")
            .union(.controlCharacters)
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_")
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    private static func mediaKind(
        for contentType: UTType?,
        filename: String
    ) -> ChatMessage.Kind {
        if contentType?.conforms(to: .image) == true { return .photo }
        if contentType?.conforms(to: .movie) == true { return .video }
        if contentType?.conforms(to: .audio) == true { return .audio }

        let fallback = UTType(
            filenameExtension: URL(fileURLWithPath: filename).pathExtension
        )
        if fallback?.conforms(to: .image) == true { return .photo }
        if fallback?.conforms(to: .movie) == true { return .video }
        if fallback?.conforms(to: .audio) == true { return .audio }
        return .attachment
    }
}
