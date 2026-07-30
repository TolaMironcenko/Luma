import Foundation

struct Conversation: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case direct
        case group
    }

    let id: String
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

    init(
        jid: String,
        displayName: String? = nil,
        lastMessage: String = "",
        lastActivity: Date = .distantPast,
        unreadCount: Int = 0,
        isOnline: Bool = false,
        isPinned: Bool = false,
        encryptionPreference: EncryptionPreference = .inheritGlobal,
        kind: Kind = .direct,
        groupNickname: String? = nil,
        isGroupJoined: Bool = false,
        shouldAutojoin: Bool = false,
        occupantCount: Int = 0,
        invitedBy: String? = nil
    ) {
        let normalized = jid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.id = normalized
        self.jid = normalized
        self.displayName = displayName?.nilIfBlank ?? normalized
        self.lastMessage = lastMessage
        self.lastActivity = lastActivity
        self.unreadCount = unreadCount
        self.isOnline = isOnline
        self.isPinned = isPinned
        self.encryptionPreference = encryptionPreference
        self.kind = kind
        self.groupNickname = groupNickname?.nilIfBlank
        self.isGroupJoined = isGroupJoined
        self.shouldAutojoin = shouldAutojoin
        self.occupantCount = max(0, occupantCount)
        self.invitedBy = invitedBy?.nilIfBlank
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case jid
        case displayName
        case lastMessage
        case lastActivity
        case unreadCount
        case isOnline
        case isPinned
        case encryptionPreference
        case kind
        case groupNickname
        case isGroupJoined
        case shouldAutojoin
        case occupantCount
        case invitedBy
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        jid = try values.decode(String.self, forKey: .jid)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? jid.lowercased()
        displayName = try values.decode(String.self, forKey: .displayName)
        lastMessage = try values.decode(String.self, forKey: .lastMessage)
        lastActivity = try values.decode(Date.self, forKey: .lastActivity)
        unreadCount = try values.decode(Int.self, forKey: .unreadCount)
        isOnline = try values.decode(Bool.self, forKey: .isOnline)
        isPinned = try values.decode(Bool.self, forKey: .isPinned)
        encryptionPreference = try values.decodeIfPresent(
            EncryptionPreference.self,
            forKey: .encryptionPreference
        ) ?? .inheritGlobal
        kind = try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .direct
        groupNickname = try values.decodeIfPresent(String.self, forKey: .groupNickname)
        isGroupJoined = try values.decodeIfPresent(Bool.self, forKey: .isGroupJoined) ?? false
        shouldAutojoin = try values.decodeIfPresent(Bool.self, forKey: .shouldAutojoin) ?? false
        occupantCount = max(0, try values.decodeIfPresent(Int.self, forKey: .occupantCount) ?? 0)
        invitedBy = try values.decodeIfPresent(String.self, forKey: .invitedBy)
    }

    var isGroup: Bool { kind == .group }

    var initials: String {
        let source = displayName == jid ? (jid.split(separator: "@").first.map(String.init) ?? jid) : displayName
        let words = source.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first)
        if letters.isEmpty {
            return String(source.prefix(1)).uppercased()
        }
        return String(letters).uppercased()
    }

    var colorSeed: UInt64 {
        jid.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
