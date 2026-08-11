import Foundation

struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    enum Direction: String, Codable, Sendable {
        case incoming
        case outgoing
    }

    enum Delivery: String, Codable, Sendable {
        case sending
        case sent
        case delivered
        case failed
    }

    enum Security: String, Codable, Sendable {
        case omemo
        case plaintext
        case decryptionFailed
    }

    enum Kind: String, Codable, Sendable {
        case text
        case attachment
        case photo
        case video
        case audio
        case voice
        case videoNote
        case location
        case system

        var isMedia: Bool {
            switch self {
            case .attachment, .photo, .video, .audio, .voice, .videoNote:
                return true
            case .text, .location, .system:
                return false
            }
        }
    }

    let id: String
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

    init(
        id: String = UUID().uuidString,
        conversationID: String,
        senderJID: String,
        body: String,
        timestamp: Date = Date(),
        direction: Direction,
        delivery: Delivery,
        security: Security,
        kind: Kind = .text,
        remoteAttachmentURL: String? = nil,
        localFilename: String? = nil,
        mimeType: String? = nil,
        duration: TimeInterval? = nil,
        byteCount: Int? = nil,
        encryptionFingerprint: String? = nil,
        editedAt: Date? = nil,
        replyToID: String? = nil,
        replyToJID: String? = nil,
        replyPreview: String? = nil,
        forwardedFrom: String? = nil,
        retractedAt: Date? = nil,
        originID: String? = nil,
        stanzaID: String? = nil,
        senderDisplayName: String? = nil,
        isGroupMessage: Bool = false,
        callHistory: CallHistoryMetadata? = nil,
        reactions: [MessageReaction] = []
    ) {
        self.id = id
        self.conversationID = conversationID.lowercased()
        self.senderJID = Self.normalizedSenderJID(senderJID)
        self.body = body
        self.timestamp = timestamp
        self.direction = direction
        self.delivery = delivery
        self.security = security
        self.kind = kind
        self.remoteAttachmentURL = remoteAttachmentURL
        self.localFilename = localFilename
        self.mimeType = mimeType
        self.duration = duration
        self.byteCount = byteCount
        self.encryptionFingerprint = encryptionFingerprint
        self.editedAt = editedAt
        self.replyToID = replyToID
        self.replyToJID = replyToJID.map(Self.normalizedSenderJID)
        self.replyPreview = replyPreview
        self.forwardedFrom = forwardedFrom
        self.retractedAt = retractedAt
        self.originID = originID ?? (direction == .outgoing ? id : nil)
        self.stanzaID = stanzaID
        self.senderDisplayName = senderDisplayName
        self.isGroupMessage = isGroupMessage
        self.callHistory = callHistory
        self.reactions = reactions
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case conversationID
        case senderJID
        case body
        case timestamp
        case direction
        case delivery
        case security
        case kind
        case remoteAttachmentURL
        case localFilename
        case mimeType
        case duration
        case byteCount
        case encryptionFingerprint
        case editedAt
        case replyToID
        case replyToJID
        case replyPreview
        case forwardedFrom
        case retractedAt
        case originID
        case stanzaID
        case senderDisplayName
        case isGroupMessage
        case callHistory
        case reactions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        conversationID = try values.decode(String.self, forKey: .conversationID).lowercased()
        senderJID = Self.normalizedSenderJID(try values.decode(String.self, forKey: .senderJID))
        body = try values.decode(String.self, forKey: .body)
        timestamp = try values.decode(Date.self, forKey: .timestamp)
        direction = try values.decode(Direction.self, forKey: .direction)
        delivery = try values.decode(Delivery.self, forKey: .delivery)
        security = try values.decode(Security.self, forKey: .security)
        kind = try values.decode(Kind.self, forKey: .kind)
        remoteAttachmentURL = try values.decodeIfPresent(String.self, forKey: .remoteAttachmentURL)
        localFilename = try values.decodeIfPresent(String.self, forKey: .localFilename)
        mimeType = try values.decodeIfPresent(String.self, forKey: .mimeType)
        duration = try values.decodeIfPresent(TimeInterval.self, forKey: .duration)
        byteCount = try values.decodeIfPresent(Int.self, forKey: .byteCount)
        encryptionFingerprint = try values.decodeIfPresent(String.self, forKey: .encryptionFingerprint)
        editedAt = try values.decodeIfPresent(Date.self, forKey: .editedAt)
        replyToID = try values.decodeIfPresent(String.self, forKey: .replyToID)
        replyToJID = try values.decodeIfPresent(String.self, forKey: .replyToJID).map(Self.normalizedSenderJID)
        replyPreview = try values.decodeIfPresent(String.self, forKey: .replyPreview)
        forwardedFrom = try values.decodeIfPresent(String.self, forKey: .forwardedFrom)
        retractedAt = try values.decodeIfPresent(Date.self, forKey: .retractedAt)
        originID = try values.decodeIfPresent(String.self, forKey: .originID)
        stanzaID = try values.decodeIfPresent(String.self, forKey: .stanzaID)
        senderDisplayName = try values.decodeIfPresent(String.self, forKey: .senderDisplayName)
        isGroupMessage = try values.decodeIfPresent(Bool.self, forKey: .isGroupMessage) ?? false
        callHistory = try values.decodeIfPresent(CallHistoryMetadata.self, forKey: .callHistory)
        reactions = try values.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
    }

    var canBeEdited: Bool {
        !isRetracted
            && !isGroupMessage
            && direction == .outgoing
            && kind == .text
            && (delivery == .sent || delivery == .delivered)
    }

    var isRetracted: Bool {
        retractedAt != nil
    }

    var canBeRepliedTo: Bool {
        !isRetracted
            && kind != .system
            && (!isGroupMessage || stanzaID != nil)
    }

    var canBeForwarded: Bool {
        !isRetracted && kind != .system
    }

    var canBeRetracted: Bool {
        direction == .outgoing
            && !isGroupMessage
            && !isRetracted
            && kind != .system
            && (delivery == .sent || delivery == .delivered)
    }

    var replyIdentifier: String? {
        isGroupMessage ? stanzaID : id
    }

    var quotePreview: String {
        if isRetracted { return "Сообщение удалено" }
        let value = kind == .text ? body : previewText
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 140 else { return normalized }
        return String(normalized.prefix(137)) + "…"
    }

    var previewText: String {
        if isRetracted { return "🚫 Сообщение удалено" }
        if let callHistory {
            let icon = callHistory.isVideo ? "🎥" : "📞"
            return "\(icon) \(callTitle)"
        }
        switch kind {
        case .attachment:
            return "📎 \(localFilename ?? "Вложение")"
        case .photo:
            return "📷 Фото"
        case .video:
            return "🎬 Видео"
        case .audio:
            return "🎵 \(localFilename ?? "Аудио")"
        case .voice:
            return "🎙 Голосовое сообщение"
        case .videoNote:
            return "⭕️ Видеосообщение"
        case .location:
            return "📍 Геопозиция"
        case .text, .system:
            return body
        }
    }

    var callTitle: String {
        guard let callHistory else { return body }
        let media = callHistory.isVideo ? "видеозвонок" : "аудиозвонок"
        switch callHistory.outcome {
        case .completed:
            return direction == .incoming ? "Входящий \(media)" : "Исходящий \(media)"
        case .declined:
            return "Отклонённый \(media)"
        case .missed:
            return "Пропущенный \(media)"
        case .cancelled:
            return "Отменённый \(media)"
        case .unanswered:
            return "Нет ответа"
        case .failed:
            return "Неудачный \(media)"
        case .answeredElsewhere:
            return "Звонок принят на другом устройстве"
        }
    }

    var callSubtitle: String? {
        guard let callHistory else { return nil }
        switch callHistory.outcome {
        case .completed:
            guard let duration else { return "Звонок завершён" }
            return "Длительность \(Self.formattedCallDuration(duration))"
        case .declined:
            return direction == .incoming
                ? "Вы отклонили звонок"
                : "Собеседник отклонил звонок"
        case .missed:
            return "Вы не ответили"
        case .cancelled:
            return direction == .outgoing
                ? "Вы отменили вызов"
                : "Собеседник отменил вызов"
        case .unanswered:
            return "Собеседник не ответил"
        case .failed:
            return "Соединение не установлено"
        case .answeredElsewhere:
            return "Ответ с другого устройства"
        }
    }

    private static func formattedCallDuration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        if seconds >= 3_600 {
            return String(
                format: "%d:%02d:%02d",
                seconds / 3_600,
                (seconds % 3_600) / 60,
                seconds % 60
            )
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func normalizedSenderJID(_ value: String) -> String {
        guard let slash = value.firstIndex(of: "/") else { return value.lowercased() }
        let bare = value[..<slash].lowercased()
        return bare + String(value[slash...])
    }
}
