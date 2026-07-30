import Foundation

struct AttachmentDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let filename: String
    let mimeType: String
    let kind: ChatMessage.Kind
    let duration: TimeInterval?
    let byteCount: Int
    let thumbnailData: Data?
    let isTemporary: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        filename: String,
        mimeType: String,
        kind: ChatMessage.Kind,
        duration: TimeInterval? = nil,
        byteCount: Int,
        thumbnailData: Data? = nil,
        isTemporary: Bool = true
    ) {
        self.id = id
        self.url = url
        self.filename = filename
        self.mimeType = mimeType
        self.kind = kind
        self.duration = duration
        self.byteCount = byteCount
        self.thumbnailData = thumbnailData
        self.isTemporary = isTemporary
    }
}

struct AttachmentBatchResult: Sendable {
    let sentCount: Int
    let failedDrafts: [AttachmentDraft]
    let captionSent: Bool

    var isComplete: Bool {
        failedDrafts.isEmpty
    }
}
