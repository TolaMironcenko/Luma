import Foundation
import SwiftData

/// SwiftData-backed replacement for the legacy JSON `ChatArchive`. Owns the
/// per-account `ModelContainer`/`ModelContext`, imports the old JSON snapshot
/// once, and exposes load/save/erase.
@MainActor
final class ArchiveStore {
    struct Loaded {
        var conversations: [Conversation]
        var messages: [ChatMessage]
        var locallyDeletedMessageIDs: Set<String>
        var rosterContactJIDs: Set<String>
        var lastSuccessfulMAMSync: Date?
        var lastSuccessfulMAMCursor: String?
        var mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint]
    }

    let container: ModelContainer
    let context: ModelContext
    private let accountJID: String
    private let storeURL: URL
    private let legacyJSONURL: URL
    private(set) var metadata: ArchiveMetadata?

    init(accountJID: String) throws {
        self.accountJID = accountJID
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Luma/Accounts", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let hash = Self.stableHash(accountJID)
        storeURL = directory.appendingPathComponent("\(hash).store")
        legacyJSONURL = directory.appendingPathComponent("\(hash).json")

        let schema = Schema([
            Conversation.self,
            ChatMessage.self,
            ArchiveMetadata.self,
        ])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false

        migrateLegacyJSONIfNeeded()
    }

    func load() -> Loaded {
        let conversationSort = [SortDescriptor(\Conversation.lastActivity, order: .reverse)]
        let conversations = (try? context.fetch(FetchDescriptor<Conversation>(sortBy: conversationSort))) ?? []
        let messages = (try? context.fetch(FetchDescriptor<ChatMessage>())) ?? []

        let metadata = fetchMetadata()
        let mamCheckpoints = Dictionary(
            metadata.mamCheckpoints.map { ($0.key, $0.checkpoint) },
            uniquingKeysWith: { first, _ in first }
        )

        return Loaded(
            conversations: conversations,
            messages: messages,
            locallyDeletedMessageIDs: Set(metadata.locallyDeletedMessageIDs),
            rosterContactJIDs: Set(metadata.rosterContactJIDs),
            lastSuccessfulMAMSync: metadata.lastSuccessfulMAMSync,
            lastSuccessfulMAMCursor: metadata.lastSuccessfulMAMCursor,
            mamCheckpoints: mamCheckpoints
        )
    }

    /// Persists the passed metadata plus all pending model mutations.
    func save(
        locallyDeletedMessageIDs: Set<String>,
        rosterContactJIDs: Set<String>,
        lastSuccessfulMAMSync: Date?,
        lastSuccessfulMAMCursor: String?,
        mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint]
    ) throws {
        let metadata = fetchMetadata()
        metadata.locallyDeletedMessageIDs = Array(locallyDeletedMessageIDs)
        metadata.rosterContactJIDs = Array(rosterContactJIDs)
        metadata.lastSuccessfulMAMSync = lastSuccessfulMAMSync
        metadata.lastSuccessfulMAMCursor = ArchiveSyncCheckpoint.normalizedCursor(lastSuccessfulMAMCursor)
        metadata.mamCheckpoints = mamCheckpoints.map {
            MAMCheckpointEntry(key: $0.key, checkpoint: $0.value)
        }
        try context.save()
    }

    func erase() throws {
        try context.delete(model: Conversation.self)
        try context.delete(model: ChatMessage.self)
        try context.delete(model: ArchiveMetadata.self)
        try context.save()
    }

    private func fetchMetadata() -> ArchiveMetadata {
        if let metadata { return metadata }
        let existing = try? context.fetch(FetchDescriptor<ArchiveMetadata>()).first
        let metadata = existing ?? ArchiveMetadata(accountJID: accountJID)
        context.insert(metadata)
        self.metadata = metadata
        return metadata
    }

    private func migrateLegacyJSONIfNeeded() {
        guard FileManager.default.fileExists(atPath: legacyJSONURL.path) else { return }
        guard let imported = try? LegacyArchiveImporter.importIfNeeded(from: legacyJSONURL) else {
            return
        }
        for conversation in imported.conversations {
            context.insert(conversation)
        }
        for message in imported.messages {
            context.insert(message)
        }
        let metadata = fetchMetadata()
        metadata.locallyDeletedMessageIDs = imported.locallyDeletedMessageIDs
        metadata.rosterContactJIDs = imported.rosterContactJIDs
        metadata.lastSuccessfulMAMSync = imported.lastSuccessfulMAMSync
        metadata.lastSuccessfulMAMCursor = imported.lastSuccessfulMAMCursor
        metadata.mamCheckpoints = imported.mamCheckpoints
        try? context.save()
        try? FileManager.default.removeItem(at: legacyJSONURL)
    }

    private static func stableHash(_ value: String) -> String {
        let hash = value.lowercased().utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16, uppercase: false)
    }
}
