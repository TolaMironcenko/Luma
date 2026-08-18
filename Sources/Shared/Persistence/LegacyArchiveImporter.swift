import Foundation

/// Reads the legacy JSON snapshot and converts it into SwiftData `@Model`
/// objects once, so existing history survives the migration from the JSON file.
enum LegacyArchiveImporter {
    struct LegacyConversation: Codable {
        enum Kind: String, Codable { case direct, group }
        var id: String
        var jid: String
        var displayName: String
        var lastMessage: String
        var lastActivity: Date
        var unreadCount: Int
        var isOnline: Bool
        var isPinned: Bool
        var encryptionPreference: EncryptionPreference
        var kind: Kind
        var groupNickname: String?
        var isGroupJoined: Bool
        var shouldAutojoin: Bool
        var occupantCount: Int
        var invitedBy: String?
    }

    struct LegacyMessage: Codable {
        enum Direction: String, Codable { case incoming, outgoing }
        enum Delivery: String, Codable { case sending, sent, delivered, failed }
        enum Security: String, Codable { case omemo, plaintext, decryptionFailed }
        enum Kind: String, Codable {
            case text, attachment, photo, video, audio, voice, videoNote, location, system
        }
        var id: String
        var conversationID: String
        var senderJID: String
        var body: String
        var timestamp: Date
        var direction: Direction
        var delivery: Delivery
        var security: Security
        var kind: Kind
        var remoteAttachmentURL: String?
        var localFilename: String?
        var mimeType: String?
        var duration: TimeInterval?
        var byteCount: Int?
        var encryptionFingerprint: String?
        var editedAt: Date?
        var replyToID: String?
        var replyToJID: String?
        var replyPreview: String?
        var forwardedFrom: String?
        var retractedAt: Date?
        var originID: String?
        var stanzaID: String?
        var senderDisplayName: String?
        var isGroupMessage: Bool
        var callHistory: CallHistoryMetadata?
        var reactions: [MessageReaction]
    }

    struct Snapshot: Codable {
        var schemaVersion: Int
        var conversations: [LegacyConversation]
        var messages: [LegacyMessage]
        var locallyDeletedMessageIDs: Set<String>
        var rosterContactJIDs: Set<String>
        var lastSuccessfulMAMSync: Date?
        var lastSuccessfulMAMCursor: String?
        var mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint]
    }

    struct Imported {
        let conversations: [Conversation]
        let messages: [ChatMessage]
        let locallyDeletedMessageIDs: [String]
        let rosterContactJIDs: [String]
        let lastSuccessfulMAMSync: Date?
        let lastSuccessfulMAMCursor: String?
        let mamCheckpoints: [MAMCheckpointEntry]
    }

    static func importIfNeeded(from url: URL) throws -> Imported? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(Snapshot.self, from: data)

        let conversations = snapshot.conversations.map { legacy -> Conversation in
            let conversation = Conversation(
                jid: legacy.jid,
                displayName: legacy.displayName,
                lastMessage: legacy.lastMessage,
                lastActivity: legacy.lastActivity,
                unreadCount: legacy.unreadCount,
                isOnline: legacy.isOnline,
                isPinned: legacy.isPinned,
                encryptionPreference: legacy.encryptionPreference,
                kind: legacy.kind == .group ? .group : .direct,
                groupNickname: legacy.groupNickname,
                isGroupJoined: legacy.isGroupJoined,
                shouldAutojoin: legacy.shouldAutojoin,
                occupantCount: legacy.occupantCount,
                invitedBy: legacy.invitedBy
            )
            return conversation
        }

        let conversationByJID = Dictionary(
            conversations.map { ($0.jid, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let messages = snapshot.messages.map { legacy -> ChatMessage in
            let message = ChatMessage(
                id: legacy.id,
                conversationID: legacy.conversationID,
                senderJID: legacy.senderJID,
                body: legacy.body,
                timestamp: legacy.timestamp,
                direction: legacy.direction == .outgoing ? .outgoing : .incoming,
                delivery: ChatMessage.Delivery(rawValue: legacy.delivery.rawValue) ?? .sent,
                security: ChatMessage.Security(rawValue: legacy.security.rawValue) ?? .plaintext,
                kind: ChatMessage.Kind(rawValue: legacy.kind.rawValue) ?? .text,
                remoteAttachmentURL: legacy.remoteAttachmentURL,
                localFilename: legacy.localFilename,
                mimeType: legacy.mimeType,
                duration: legacy.duration,
                byteCount: legacy.byteCount,
                encryptionFingerprint: legacy.encryptionFingerprint,
                editedAt: legacy.editedAt,
                replyToID: legacy.replyToID,
                replyToJID: legacy.replyToJID,
                replyPreview: legacy.replyPreview,
                forwardedFrom: legacy.forwardedFrom,
                retractedAt: legacy.retractedAt,
                originID: legacy.originID,
                stanzaID: legacy.stanzaID,
                senderDisplayName: legacy.senderDisplayName,
                isGroupMessage: legacy.isGroupMessage,
                callHistory: legacy.callHistory,
                reactions: legacy.reactions
            )
            message.conversation = conversationByJID[legacy.conversationID.lowercased()]
            return message
        }

        return Imported(
            conversations: conversations,
            messages: messages,
            locallyDeletedMessageIDs: Array(snapshot.locallyDeletedMessageIDs),
            rosterContactJIDs: Array(snapshot.rosterContactJIDs),
            lastSuccessfulMAMSync: snapshot.lastSuccessfulMAMSync,
            lastSuccessfulMAMCursor: snapshot.lastSuccessfulMAMCursor,
            mamCheckpoints: snapshot.mamCheckpoints.map {
                MAMCheckpointEntry(key: $0.key, checkpoint: $0.value)
            }
        )
    }
}
