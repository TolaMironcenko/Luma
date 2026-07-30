import Foundation
import XCTest
@testable import Luma

final class MediaFileIOTests: XCTestCase {
    func testStagedDraftSurvivesThePickerURLBeingRemoved() async throws {
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        let source = sourceDirectory.appendingPathComponent("photo.jpg")
        let payload = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try payload.write(to: source)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        let staged = try await MediaFileIO().stageAttachmentDraft(from: source)
        defer { try? FileManager.default.removeItem(at: staged.url) }
        try FileManager.default.removeItem(at: source)

        XCTAssertEqual(staged.filename, "photo.jpg")
        XCTAssertEqual(staged.byteCount, payload.count)
        XCTAssertEqual(try Data(contentsOf: staged.url), payload)
    }

    func testEmptyPickerFileIsRejectedBeforePreviewOrUpload() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString).mov")
        try Data().write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        do {
            _ = try await MediaFileIO().stageAttachmentDraft(from: source)
            XCTFail("An empty media file must not become a sendable draft")
        } catch MediaFileIOError.emptyFile(_) {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
