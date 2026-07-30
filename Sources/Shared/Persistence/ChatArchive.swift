import Foundation

actor ChatArchive {
    struct Snapshot: Codable, Sendable {
        static let currentSchemaVersion = 5

        var schemaVersion: Int
        var conversations: [Conversation]
        var messages: [ChatMessage]
        var locallyDeletedMessageIDs: Set<String>
        var rosterContactJIDs: Set<String>
        var lastSuccessfulMAMSync: Date?
        var lastSuccessfulMAMCursor: String?

        init(
            conversations: [Conversation],
            messages: [ChatMessage],
            locallyDeletedMessageIDs: Set<String> = [],
            rosterContactJIDs: Set<String> = [],
            lastSuccessfulMAMSync: Date? = nil,
            lastSuccessfulMAMCursor: String? = nil
        ) {
            self.schemaVersion = Self.currentSchemaVersion
            self.conversations = conversations
            self.messages = messages
            self.locallyDeletedMessageIDs = locallyDeletedMessageIDs
            self.rosterContactJIDs = rosterContactJIDs
            self.lastSuccessfulMAMSync = lastSuccessfulMAMSync
            self.lastSuccessfulMAMCursor = ArchiveSyncCheckpoint.normalizedCursor(
                lastSuccessfulMAMCursor
            )
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case conversations
            case messages
            case locallyDeletedMessageIDs
            case rosterContactJIDs
            case lastSuccessfulMAMSync
            case lastSuccessfulMAMCursor
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            conversations = try values.decode([Conversation].self, forKey: .conversations)
            messages = try values.decode([ChatMessage].self, forKey: .messages)
            locallyDeletedMessageIDs = try values.decodeIfPresent(
                Set<String>.self,
                forKey: .locallyDeletedMessageIDs
            ) ?? []
            rosterContactJIDs = try values.decodeIfPresent(
                Set<String>.self,
                forKey: .rosterContactJIDs
            ) ?? []
            lastSuccessfulMAMSync = try values.decodeIfPresent(
                Date.self,
                forKey: .lastSuccessfulMAMSync
            )
            lastSuccessfulMAMCursor = ArchiveSyncCheckpoint.normalizedCursor(
                try values.decodeIfPresent(String.self, forKey: .lastSuccessfulMAMCursor)
            )
        }

        static let empty = Snapshot(conversations: [], messages: [])
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(accountJID: String) {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Luma/Accounts", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("\(Self.stableHash(accountJID)).json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    func save(_ snapshot: Snapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
#if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
#endif
    }

    func erase() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func stableHash(_ value: String) -> String {
        let hash = value.lowercased().utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16, uppercase: false)
    }
}
