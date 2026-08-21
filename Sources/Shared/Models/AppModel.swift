import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers
import WebRTC

enum RuntimeEnvironment {
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var account: AccountConfiguration?
    @Published private(set) var connectionStatus: XMPPService.ConnectionStatus = .disconnected(
        reason: nil)
    private(set) var conversations: [Conversation] = [] {
        willSet {
            if !isApplyingArchiveBatch {
                objectWillChange.send()
            }
        }
    }
    @Published private(set) var rosterContactJIDs: Set<String> = []
    private(set) var messages: [ChatMessage] = [] {
        willSet {
            if !isApplyingArchiveBatch {
                objectWillChange.send()
            }
        }
        didSet {
            if !isApplyingArchiveBatch {
                selectedMessagesCacheConversationID = nil
                selectedTimelineEntriesCacheConversationID = nil
            }
        }
    }
    @Published var selectedConversationID: String?
    @Published private(set) var isOMEMOReady = false
    @Published private(set) var ownFingerprint: String?
    @Published private(set) var serverInformation: ServerInformation?
    @Published private(set) var isArchiveSyncing = false
    @Published private(set) var isLoadingOlderHistory = false
    @Published private(set) var hasMoreOlderHistory = true
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isSendingAttachment = false
    @Published private(set) var isUpdatingAvatar = false
    @Published private(set) var avatarDataByJID: [String: Data] = [:]
    @Published private(set) var globalEncryptionEnabled = true
    @Published private(set) var typingIndicatorsEnabled = true
    @Published private(set) var typingParticipantsByConversation: [String: [String: String]] = [:]
    @Published var errorMessage: String?
    @Published var informationalMessage: String?
    @Published var previewURL: URL?
    @Published private(set) var mediaViewerItem: MediaViewerItem?
    @Published private(set) var mediaPreviewURLs: [String: URL] = [:]
    @Published private(set) var mediaThumbnailData: [String: Data] = [:]
    @Published private(set) var audioWaveformSamples: [String: [Float]] = [:]
    @Published private(set) var loadingMediaIDs: Set<String> = []
    @Published private(set) var activeCall: CallSnapshot?

    let audioPlayback = MediaPlaybackCoordinator()

    private let xmpp: XMPPService
    private let credentials: CredentialVault
    private let preferences: AccountPreferences
    private let notifications: NotificationCoordinator
    private let watchBridge: PhoneWatchBridge
    private let avatarCache: AvatarCache
    private let mediaPreviewProcessor = MediaPreviewProcessor()
    private let mediaFileIO = MediaFileIO()
    private var store: ArchiveStore?
    private var bootstrapTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var watchSyncTask: Task<Void, Never>?
    private var isApplyingArchiveBatch = false
    private var messageIndexByStorageKey: [String: Int] = [:]
    private var messageIndexByStanzaKey: [String: Int] = [:]
    private var messageIndexByOriginKey: [String: Int] = [:]
    private var firstMessageIndexByID: [String: Int] = [:]
    private var selectedMessagesCacheConversationID: String?
    private var selectedMessagesCache: [ChatMessage] = []
    private var selectedTimelineEntriesCacheConversationID: String?
    private var selectedTimelineEntriesCache: [ChatTimelineEntry] = []
    private var appIsActive = true
    private var avatarCacheRequests: Set<String> = []
    private var pendingCorrections: [String: XMPPService.MessageEnvelope] = [:]
    private var pendingRetractions: [String: XMPPService.RetractionEnvelope] = [:]
    private var pendingReactions: [String: XMPPService.ReactionEnvelope] = [:]
    private var correctionReceiptTargets: [String: String] = [:]
    private var localChatStateByConversation: [String: ChatTypingState] = [:]
    private var localTypingPauseTasks: [String: Task<Void, Never>] = [:]
    private var remoteTypingExpiryTasks: [String: Task<Void, Never>] = [:]
    private var locallyDeletedMessageIDs: Set<String> = []
    private var lastSuccessfulMAMSync: Date?
    private var lastSuccessfulMAMCursor: String?
    private var mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint] = [:]
    private var hasMoreOlderHistoryByConversation: [String: Bool] = [:]
    private var pendingRoomPasswords: [String: String] = [:]
    private var joiningRoomJIDs: Set<String> = []
    private var mediaSendActivity = MediaSendActivityTracker()
    private var mediaPreparationTokens: Set<UUID> = []
    private var videoNoteCaptureIsActive = false
    private var archiveSyncIsSuspendedForMedia = false

    init(
        xmpp: XMPPService? = nil,
        credentials: CredentialVault = CredentialVault(),
        preferences: AccountPreferences = AccountPreferences(),
        notifications: NotificationCoordinator = NotificationCoordinator(),
        watchBridge: PhoneWatchBridge = PhoneWatchBridge(),
        avatarCache: AvatarCache = AvatarCache()
    ) {
        // Default arguments are evaluated at the call site, which may be
        // nonisolated. Construct the @MainActor service inside this
        // @MainActor initializer instead.
        let xmpp = xmpp ?? XMPPService()
        self.xmpp = xmpp
        self.credentials = credentials
        self.preferences = preferences
        self.notifications = notifications
        self.watchBridge = watchBridge
        self.avatarCache = avatarCache

        xmpp.eventHandler = { [weak self] event in
            self?.consume(event)
        }
        watchBridge.onReply = { [weak self] jid, text in
            Task { @MainActor in
                guard let self else { return }
                if !self.conversations.contains(where: { $0.jid == jid.lowercased() }) {
                    self.upsertConversation(jid: jid, name: nil)
                }
                await self.sendText(text, to: jid)
            }
        }
        watchBridge.onVoiceMessage = { [weak self] voice in
            Task { @MainActor in
                guard let self else { return }
                self.errorMessage = nil
                if let bootstrapTask = self.bootstrapTask {
                    await bootstrapTask.value
                }

                guard self.account != nil else {
                    let error =
                        "Войдите в XMPP-аккаунт на iPhone, затем повторите отправку с Apple Watch."
                    self.errorMessage = error
                    self.watchBridge.reportVoiceResult(
                        transferID: voice.transferID,
                        success: false,
                        error: error
                    )
                    return
                }

                if self.connectionStatus != .connected {
                    await self.reconnect()
                }
                guard self.connectionStatus == .connected else {
                    let error = self.errorMessage ?? "iPhone не подключён к XMPP-серверу."
                    self.errorMessage = error
                    self.watchBridge.reportVoiceResult(
                        transferID: voice.transferID,
                        success: false,
                        error: error
                    )
                    return
                }

                if !self.conversations.contains(where: { $0.jid == voice.jid.lowercased() }) {
                    self.upsertConversation(jid: voice.jid, name: nil)
                }
                let messageID = await self.sendMedia(
                    data: voice.data,
                    filename: voice.filename,
                    mimeType: "audio/mp4",
                    kind: .voice,
                    duration: voice.duration,
                    to: voice.jid,
                    messageID: voice.stableMessageID
                )
                let success = messageID != nil
                let failure =
                    success
                    ? nil : (self.errorMessage ?? "Не удалось отправить голосовое сообщение.")
                if success {
                    self.informationalMessage = "Голосовое сообщение с Apple Watch отправлено."
                } else if self.errorMessage == nil {
                    self.errorMessage = failure
                }
                self.watchBridge.reportVoiceResult(
                    transferID: voice.transferID,
                    success: success,
                    error: failure
                )
            }
        }

        if !RuntimeEnvironment.isRunningTests {
            bootstrapTask = Task { [weak self] in
                guard let self else { return }
                await self.bootstrap()
            }
        }
    }

    deinit {
        bootstrapTask?.cancel()
        persistTask?.cancel()
        watchSyncTask?.cancel()
        localTypingPauseTasks.values.forEach { $0.cancel() }
        remoteTypingExpiryTasks.values.forEach { $0.cancel() }
    }

    var selectedConversation: Conversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.jid == selectedConversationID }
    }

    private var durableArchiveSyncCheckpoint: ArchiveSyncCheckpoint? {
        guard let lastSuccessfulMAMSync else { return nil }
        return ArchiveSyncCheckpoint(
            timestamp: lastSuccessfulMAMSync,
            cursor: lastSuccessfulMAMCursor
        )
    }

    var selectedMessages: [ChatMessage] {
        guard let selectedConversationID else { return [] }
        if selectedMessagesCacheConversationID == selectedConversationID {
            return selectedMessagesCache
        }
        let sorted =
            messages
            .filter { $0.conversationID == selectedConversationID }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp { return lhs.clientID < rhs.clientID }
                return lhs.timestamp < rhs.timestamp
            }
        selectedMessagesCacheConversationID = selectedConversationID
        selectedMessagesCache = sorted
        return sorted
    }

    var selectedTimelineEntries: [ChatTimelineEntry] {
        guard let selectedConversationID else { return [] }
        if selectedTimelineEntriesCacheConversationID == selectedConversationID {
            return selectedTimelineEntriesCache
        }
        let entries = ChatTimelineEntry.make(from: selectedMessages)
        selectedTimelineEntriesCacheConversationID = selectedConversationID
        selectedTimelineEntriesCache = entries
        return entries
    }

    func bootstrap() async {
        guard !RuntimeEnvironment.isRunningTests else { return }
        guard let saved = preferences.load() else { return }
        account = saved
        globalEncryptionEnabled = preferences.encryptionEnabled(for: saved.normalizedJID)
        typingIndicatorsEnabled = preferences.chatStatesEnabled(for: saved.normalizedJID)
        xmpp.setChatStatesEnabled(typingIndicatorsEnabled)
        await loadArchive(for: saved.normalizedJID)
        let password: String
        do {
            guard let storedPassword = try credentials.password(for: saved.normalizedJID) else {
                account = nil
                store = nil
                conversations = []
                rosterContactJIDs = []
                messages = []
                rebuildMessageIndex()
                informationalMessage = "Введите пароль заново: запись Keychain не найдена."
                return
            }
            password = storedPassword
        } catch {
            account = nil
            store = nil
            conversations = []
            rosterContactJIDs = []
            messages = []
            rebuildMessageIndex()
            errorMessage = error.localizedDescription
            return
        }
        do {
            try await xmpp.connect(
                account: saved,
                password: password,
                archiveCheckpoint: durableArchiveSyncCheckpoint,
                mamCheckpoints: mamCheckpoints
            )
            await notifications.requestAuthorization()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(account: AccountConfiguration, password: String) async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let account = try account.validated()
            guard !password.isEmpty else { throw SignInError.emptyPassword }

            resetArchiveBatchState()
            avatarDataByJID = [:]
            avatarCacheRequests = []
            pendingCorrections = [:]
            pendingRetractions = [:]
            pendingReactions = [:]
            correctionReceiptTargets = [:]
            locallyDeletedMessageIDs = []
            pendingRoomPasswords = [:]
            joiningRoomJIDs = []
            rosterContactJIDs = []
            resetMediaSendActivity()
            resetMediaPreviews()
            self.account = account
            globalEncryptionEnabled = preferences.encryptionEnabled(for: account.normalizedJID)
            typingIndicatorsEnabled = preferences.chatStatesEnabled(for: account.normalizedJID)
            xmpp.setChatStatesEnabled(typingIndicatorsEnabled)
            await loadArchive(for: account.normalizedJID)
            try await xmpp.connect(
                account: account,
                password: password,
                archiveCheckpoint: durableArchiveSyncCheckpoint,
                mamCheckpoints: mamCheckpoints
            )
            try credentials.save(password: password, for: account.normalizedJID)
            try preferences.save(account)
            await notifications.requestAuthorization()
        } catch {
            await xmpp.disconnect()
            self.account = nil
            store = nil
            conversations = []
            rosterContactJIDs = []
            messages = []
            rebuildMessageIndex()
            errorMessage = error.localizedDescription
        }
    }

    func signOut(forgetHistory: Bool = false) async {
        let oldAccount = account
        await xmpp.disconnect()
        preferences.clear()
        if let oldAccount {
            try? credentials.deletePassword(for: oldAccount.normalizedJID)
            if forgetHistory {
                try? store?.erase()
            }
        }
        persistTask?.cancel()
        resetArchiveBatchState()
        watchSyncTask?.cancel()
        watchSyncTask = nil
        store = nil
        account = nil
        conversations = []
        rosterContactJIDs = []
        messages = []
        rebuildMessageIndex()
        selectedConversationID = nil
        isOMEMOReady = false
        ownFingerprint = nil
        avatarDataByJID = [:]
        avatarCacheRequests = []
        globalEncryptionEnabled = true
        typingIndicatorsEnabled = true
        isUpdatingAvatar = false
        errorMessage = nil
        previewURL = nil
        pendingCorrections = [:]
        pendingRetractions = [:]
        pendingReactions = [:]
        correctionReceiptTargets = [:]
        locallyDeletedMessageIDs = []
        lastSuccessfulMAMSync = nil
        lastSuccessfulMAMCursor = nil
        pendingRoomPasswords = [:]
        joiningRoomJIDs = []
        activeCall = nil
        resetTypingState()
        resetMediaSendActivity()
        resetMediaPreviews()
    }

    func reconnect() async {
        guard !RuntimeEnvironment.isRunningTests else { return }
        guard let account else { return }
        do {
            guard let password = try credentials.password(for: account.normalizedJID) else {
                throw ReconnectError.passwordMissing
            }
            try await xmpp.reconnectIfNeeded(
                password: password, archiveCheckpoint: durableArchiveSyncCheckpoint)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setApplicationActive(_ active: Bool) {
        appIsActive = active
        guard !RuntimeEnvironment.isRunningTests else { return }
        xmpp.setApplicationActive(active)
        if !active {
            resetTypingState()
            syncWatch(immediate: true)
        }
        if active, case .disconnected(_) = connectionStatus {
            Task { await reconnect() }
        }
    }

    func setVideoNoteCaptureActive(_ active: Bool) {
        videoNoteCaptureIsActive = active
        updateArchiveSyncSuspensionForMedia()
    }

    func startCall(to rawJID: String, withVideo: Bool) async {
        let jid = rawJID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !jid.isEmpty else { return }
        guard conversations.first(where: { $0.jid == jid })?.isGroup != true else {
            errorMessage = "Звонки в текущем MVP доступны только в личных чатах."
            return
        }
        guard await requestCallPermissions(includeVideo: withVideo) else { return }
        audioPlayback.stop()
        do {
            try await xmpp.startCall(to: jid, withVideo: withVideo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func answerCall() async {
        guard let activeCall else { return }
        guard await requestCallPermissions(includeVideo: activeCall.isVideoCall) else { return }
        audioPlayback.stop()
        do {
            try await xmpp.answerCall()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rejectCall() {
        xmpp.rejectCall()
    }

    func endCall() {
        xmpp.endCall()
    }

    func setCallMuted(_ muted: Bool) {
        xmpp.setCallMuted(muted)
    }

    func setCallCameraEnabled(_ enabled: Bool) {
        xmpp.setCallCameraEnabled(enabled)
    }

    func setCallSpeakerEnabled(_ enabled: Bool) {
        xmpp.setCallSpeakerEnabled(enabled)
    }

    func switchCallCamera() {
        xmpp.switchCallCamera()
    }

    func localCallVideoTrack(for callID: UUID) -> RTCVideoTrack? {
        xmpp.localCallVideoTrack(for: callID)
    }

    func remoteCallVideoTrack(for callID: UUID) -> RTCVideoTrack? {
        xmpp.remoteCallVideoTrack(for: callID)
    }

    func openConversation(jid: String, name: String? = nil, addToRoster: Bool = false) {
        let normalized = jid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidJID(normalized) else {
            errorMessage = "Введите JID в формате user@example.org."
            return
        }
        upsertConversation(jid: normalized, name: name)
        selectedConversationID = normalized
        if let index = conversations.firstIndex(where: { $0.jid == normalized }) {
            conversations[index].unreadCount = 0
        }
        if addToRoster {
            rosterContactJIDs.insert(normalized)
            xmpp.addToRoster(jid: normalized, name: name)
        }
        xmpp.fetchAvatar(for: normalized)
        schedulePersist()
        syncWatch()
    }

    func selectConversation(id: String) {
        let normalized = id.lowercased()
        selectedConversationID = normalized
//        if let index = conversations.firstIndex(where: { $0.jid == normalized }) {
//            conversations[index].unreadCount = 0
//        }
//        schedulePersist()
//        syncWatch()
//        hasMoreOlderHistory = true
        if hasMoreOlderHistoryByConversation[normalized] == false,
           selectedMessages.isEmpty
        {
            // An empty conversation must be allowed to retry a load after a
            // previous attempt returned zero results. Otherwise it stays empty
            // with `hasMore = false` and no way to trigger loading again.
            hasMoreOlderHistoryByConversation[normalized] = true
        }
        hasMoreOlderHistory = hasMoreOlderHistoryByConversation[normalized] ?? true
    }
    
    func loadOlderHistoryForSelectedConversation() {
        guard !isLoadingOlderHistory,
              hasMoreOlderHistory,
              let conversation = selectedConversation else { return }
        //        let oldestServerID = selectedMessages
        //            .sorted { lhs, rhs in
        //                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        //                return lhs.clientID < rhs.clientID
        //            }
        //            .compactMap(\.stanzaID)
        //            .first
        let oldestServerID = selectedMessages
            .filter { $0.stanzaID != nil }
            .min { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                return lhs.clientID < rhs.clientID
            }?
            .stanzaID

        isLoadingOlderHistory = true
        let conversationID = conversation.jid.lowercased()
        xmpp.loadOlderHistory(
            conversationJID: conversation.jid,
            isGroup: conversation.isGroup,
            before: oldestServerID
        ) { [weak self] result in
            guard let self else { return }
            self.isLoadingOlderHistory = false
            switch result {
            case .success(let hasMore):
//                self.hasMoreOlderHistory = hasMore
                self.hasMoreOlderHistoryByConversation[conversationID] = hasMore
                if self.selectedConversationID == conversationID {
                    self.hasMoreOlderHistory = hasMore
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func createOrJoinGroup(
        roomJID rawRoomJID: String,
        name: String?,
        nickname rawNickname: String,
        invitees: [String]
    ) async {
        let roomJID = rawRoomJID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidJID(roomJID) else {
            errorMessage = "Введите адрес комнаты в формате room@conference.example.org."
            return
        }
        let nickname = rawNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else {
            errorMessage = "Введите псевдоним для группового чата."
            return
        }
        let validInvitees =
            invitees
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter(Self.isValidJID)

        upsertGroupConversation(
            jid: roomJID,
            name: name,
            nickname: nickname,
            shouldAutojoin: true
        )
        selectConversation(id: roomJID)
        guard joiningRoomJIDs.insert(roomJID).inserted else { return }
        defer { joiningRoomJIDs.remove(roomJID) }
        do {
            try await xmpp.joinRoom(roomJID: roomJID, nickname: nickname)
            if !validInvitees.isEmpty {
                try await xmpp.inviteMembers(validInvitees, to: roomJID)
                informationalMessage = "Приглашения отправлены: \(validInvitees.count)."
            }
        } catch {
            if let index = conversations.firstIndex(where: { $0.jid == roomJID }) {
                conversations[index].isGroupJoined = false
            }
            errorMessage = error.localizedDescription
        }
        schedulePersist()
    }

    func joinGroup(jid rawJID: String, nickname preferredNickname: String? = nil) async {
        let jid = rawJID.lowercased()
        guard let index = conversations.firstIndex(where: { $0.jid == jid && $0.isGroup }) else {
            return
        }
        guard !conversations[index].isGroupJoined,
            joiningRoomJIDs.insert(jid).inserted
        else { return }
        defer { joiningRoomJIDs.remove(jid) }
        let trimmedNickname = preferredNickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname: String
        if let trimmedNickname, !trimmedNickname.isEmpty {
            nickname = trimmedNickname
        } else {
            nickname = conversations[index].groupNickname ?? defaultGroupNickname
        }
        do {
            try await xmpp.joinRoom(
                roomJID: jid,
                nickname: nickname,
                password: pendingRoomPasswords[jid]
            )
            conversations[index].groupNickname = nickname
            conversations[index].shouldAutojoin = true
            conversations[index].invitedBy = nil
            pendingRoomPasswords.removeValue(forKey: jid)
        } catch {
            conversations[index].isGroupJoined = false
            errorMessage = error.localizedDescription
        }
        schedulePersist()
    }

    func leaveGroup(jid rawJID: String) {
        let jid = rawJID.lowercased()
        xmpp.leaveRoom(roomJID: jid)
        guard let index = conversations.firstIndex(where: { $0.jid == jid && $0.isGroup }) else {
            return
        }
        conversations[index].isGroupJoined = false
        conversations[index].shouldAutojoin = false
        conversations[index].occupantCount = 0
        schedulePersist()
    }

    func inviteMembers(_ rawJIDs: [String], to roomJID: String) async {
        let jids =
            rawJIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter(Self.isValidJID)
        guard !jids.isEmpty else {
            errorMessage = "Введите хотя бы один корректный JID участника."
            return
        }
        do {
            try await xmpp.inviteMembers(jids, to: roomJID)
            informationalMessage = "Приглашения отправлены: \(jids.count)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var suggestedGroupNickname: String { defaultGroupNickname }

    func sendText(
        _ rawText: String,
        to explicitJID: String? = nil,
        replyingTo: ChatMessage? = nil
    ) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
            let account,
            let peer = explicitJID ?? selectedConversation?.jid
        else { return }
        let conversation = conversations.first { $0.jid == peer.lowercased() }
        let isGroup = conversation?.isGroup == true
        let encrypted = encryptionEnabled(for: peer)
        let replyTarget = replyingTo.flatMap { message -> ChatMessage? in
            guard message.canBeRepliedTo,
                message.conversationID == peer.lowercased()
            else { return nil }
            return message
        }

        let id = UUID().uuidString
        let pending = ChatMessage(
            id: id,
            conversationID: peer,
            senderJID: account.normalizedJID,
            body: text,
            direction: .outgoing,
            delivery: .sending,
            security: encrypted ? .omemo : .plaintext,
            replyToID: replyTarget?.replyIdentifier,
            replyToJID: replyTarget?.senderJID,
            replyPreview: replyTarget?.quotePreview,
            senderDisplayName: isGroup ? conversation?.groupNickname : nil,
            isGroupMessage: isGroup
        )
        upsertMessage(pending)

        do {
            let fingerprint = try await xmpp.sendText(
                text,
                to: peer,
                messageID: id,
                encrypted: encrypted,
                replyTo: replyTarget.flatMap { target in
                    guard let replyID = target.replyIdentifier else { return nil }
                    return XMPPService.ReplyReference(
                        id: replyID,
                        authorJID: target.senderJID,
                        fallbackAuthor: target.senderDisplayName
                            ?? displayName(for: target.senderJID),
                        preview: target.quotePreview
                    )
                },
                isGroup: isGroup
            )
            updateMessage(id: id) {
                $0.delivery = .sent
                $0.encryptionFingerprint = fingerprint
            }
            let conversationID = peer.lowercased()
            localTypingPauseTasks[conversationID]?.cancel()
            localTypingPauseTasks[conversationID] = nil
            localChatStateByConversation[conversationID] = .active
        } catch {
            updateMessage(id: id) { $0.delivery = .failed }
            errorMessage = error.localizedDescription
        }
        schedulePersist()
        syncWatch()
    }

    func sendLocation(_ location: GeoLocation, to explicitJID: String? = nil) async {
        guard let account,
            let peer = explicitJID ?? selectedConversation?.jid
        else { return }
        let conversation = conversations.first { $0.jid == peer.lowercased() }
        let isGroup = conversation?.isGroup == true
        let encrypted = encryptionEnabled(for: peer)
        let id = UUID().uuidString
        let pending = ChatMessage(
            id: id,
            conversationID: peer,
            senderJID: account.normalizedJID,
            body: location.uriString,
            direction: .outgoing,
            delivery: .sending,
            security: encrypted ? .omemo : .plaintext,
            kind: .location,
            senderDisplayName: isGroup ? conversation?.groupNickname : nil,
            isGroupMessage: isGroup
        )
        upsertMessage(pending)

        do {
            let fingerprint = try await xmpp.sendText(
                location.uriString,
                to: peer,
                messageID: id,
                encrypted: encrypted,
                isGroup: isGroup
            )
            updateMessage(id: id) {
                $0.delivery = .sent
                $0.encryptionFingerprint = fingerprint
            }
        } catch {
            updateMessage(id: id) { $0.delivery = .failed }
            errorMessage = error.localizedDescription
        }
        schedulePersist()
        syncWatch()
    }

    func editMessage(id: String, newBody rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
            let index = messages.firstIndex(where: { $0.clientID == id }),
            messages[index].canBeEdited
        else { return }

        let previous = messages[index]
        guard text != previous.body else { return }

        let correctionID = UUID().uuidString
        let encrypted = previous.security == .omemo
        correctionReceiptTargets[correctionID] = id
        if correctionReceiptTargets.count > 100,
            let staleID = correctionReceiptTargets.keys.first(where: { $0 != correctionID })
        {
            correctionReceiptTargets.removeValue(forKey: staleID)
        }
        updateMessage(id: id) {
            $0.body = text
            $0.editedAt = Date()
            $0.delivery = .sending
        }

        do {
            let fingerprint = try await xmpp.sendText(
                text,
                to: previous.conversationID,
                messageID: correctionID,
                encrypted: encrypted,
                replacingMessageID: previous.clientID
            )
            updateMessage(id: id) {
                $0.delivery = .sent
                $0.encryptionFingerprint = fingerprint
            }
        } catch {
            correctionReceiptTargets.removeValue(forKey: correctionID)
            if let currentIndex = messages.firstIndex(where: { $0.clientID == id }),
                messages[currentIndex].delivery == .sending
            {
                messages[currentIndex] = previous
                updateConversationPreview(for: previous, incrementUnread: false)
            }
            errorMessage = error.localizedDescription
        }
        schedulePersist()
        syncWatch()
    }

    func retractMessage(id: String) async {
        guard let account,
            let message = messages.first(where: { $0.clientID == id }),
            message.canBeRetracted
        else { return }

        let retractionID = UUID().uuidString
        do {
            try await xmpp.sendRetraction(
                to: message.conversationID,
                targetID: message.clientID,
                retractionID: retractionID,
                encrypted: message.security == .omemo
            )
            applyRetraction(
                XMPPService.RetractionEnvelope(
                    peerJID: message.conversationID,
                    senderJID: account.normalizedJID,
                    targetID: message.clientID,
                    retractionID: retractionID,
                    timestamp: Date(),
                    isOutgoing: true
                ))
        } catch {
            errorMessage = error.localizedDescription
        }
        schedulePersist()
        syncWatch()
    }

    func deleteMessageLocally(id: String) {
        deleteMessagesLocally(ids: [id])
    }

    func deleteMessagesLocally(ids: Set<String>, in conversationID: String? = nil) {
        guard !ids.isEmpty else { return }
        let normalizedConversationID = conversationID?.lowercased()
        let selected = messages.filter { message in
            ids.contains(message.clientID)
                && (normalizedConversationID == nil
                    || message.conversationID == normalizedConversationID)
        }
        guard !selected.isEmpty else { return }

        let affectedConversations = Set(selected.map(\.conversationID))
        for message in selected {
            locallyDeletedMessageIDs.insert(
                Self.localDeletionKey(
                    messageID: message.clientID,
                    conversationID: message.conversationID
                ))
            let pendingKey = Self.localDeletionKey(
                messageID: message.clientID,
                conversationID: message.conversationID
            )
            pendingCorrections.removeValue(forKey: pendingKey)
            pendingRetractions.removeValue(forKey: pendingKey)
            pendingReactions = pendingReactions.filter { _, envelope in
                guard envelope.peerJID.lowercased() == message.conversationID else {
                    return true
                }
                if envelope.targetID == message.clientID { return false }
                if let stanzaID = message.stanzaID,
                    envelope.targetID == stanzaID
                {
                    return false
                }
                return true
            }
            removeCachedMedia(for: message.clientID)
        }
        let selectedKeys = Set(
            selected.map {
                Self.localDeletionKey(
                    messageID: $0.clientID,
                    conversationID: $0.conversationID
                )
            })
        messages.removeAll { message in
            selectedKeys.contains(
                Self.localDeletionKey(
                    messageID: message.clientID,
                    conversationID: message.conversationID
                ))
        }
        rebuildMessageIndex()
        for conversationID in affectedConversations {
            rebuildConversationPreview(for: conversationID)
        }
        schedulePersist()
        syncWatch()
    }

    @discardableResult
    func forwardMessage(_ message: ChatMessage, to rawRecipient: String) async -> Bool {
        await forwardMessages([message], to: rawRecipient)
    }

    @discardableResult
    func forwardMessages(_ selectedMessages: [ChatMessage], to rawRecipient: String) async -> Bool {
        let recipient =
            rawRecipient
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let forwardableMessages =
            selectedMessages
            .filter(\.canBeForwarded)
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp { return lhs.clientID < rhs.clientID }
                return lhs.timestamp < rhs.timestamp
            }
        guard !forwardableMessages.isEmpty else { return false }
        guard Self.isValidJID(recipient) else {
            errorMessage = "Введите JID в формате user@example.org."
            return false
        }

        errorMessage = nil
        upsertConversation(jid: recipient, name: nil)

        var forwardedCount = 0
        for message in forwardableMessages {
            guard await forwardMessageItem(message, to: recipient) else {
                if forwardedCount > 0 {
                    informationalMessage =
                        "Переслано сообщений: \(forwardedCount) из \(forwardableMessages.count)."
                }
                return false
            }
            forwardedCount += 1
        }
        if forwardedCount > 1 {
            informationalMessage = "Переслано сообщений: \(forwardedCount)."
        }
        return true
    }

    private func forwardMessageItem(_ message: ChatMessage, to recipient: String) async -> Bool {
        let attribution =
            "↪ Переслано от \(message.senderDisplayName ?? displayName(for: message.senderJID))"

        switch message.kind {
        case .text:
            await sendText("\(attribution)\n\(message.body)", to: recipient)
            return errorMessage == nil
        case .location:
            guard let location = GeoLocation(uri: message.body) else {
                errorMessage = "Не удалось прочитать геопозицию из сообщения."
                return false
            }
            await sendText(attribution, to: recipient)
            guard errorMessage == nil else { return false }
            await sendLocation(location, to: recipient)
            return errorMessage == nil
        case .attachment, .photo, .video, .audio, .voice, .videoNote:
            do {
                let url: URL
                if let cached = mediaPreviewURLs[message.clientID] {
                    url = cached
                } else {
                    url = try await localAttachmentURL(
                        for: message,
                        directoryName: "LumaForwarding"
                    )
                }
                let data = try await mediaFileIO.load(
                    from: url,
                    preferredKind: message.kind
                ).data
                await sendText(attribution, to: recipient)
                guard errorMessage == nil else { return false }
                let sentID = await sendMedia(
                    data: data,
                    filename: message.localFilename ?? url.lastPathComponent,
                    mimeType: message.mimeType ?? "application/octet-stream",
                    kind: message.kind,
                    duration: message.duration,
                    to: recipient
                )
                return sentID != nil
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        case .system:
            return false
        }
    }

    func message(withID id: String, in conversationID: String? = nil) -> ChatMessage? {
        guard let conversationID else {
            if let index = firstMessageIndexByID[id],
                messages.indices.contains(index),
                messages[index].clientID == id
            {
                return messages[index]
            }
            return messages.first { $0.stanzaID == id }
        }
        let normalized = conversationID.lowercased()
        guard
            let index = messageIndex(
                referenceID: id,
                conversationID: normalized
            )
        else { return nil }
        return messages[index]
    }

    func displayName(for jid: String) -> String {
        conversationName(for: jid)
    }

    @discardableResult
    func sendAttachment(
        from url: URL,
        preferredKind: ChatMessage.Kind? = nil,
        duration: TimeInterval? = nil,
        to explicitJID: String? = nil
    ) async -> String? {
        guard let peer = explicitJID ?? selectedConversation?.jid else { return nil }
        let preparationToken = beginMediaPreparationActivity()
        defer { endMediaPreparationActivity(preparationToken) }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let loaded = try await mediaFileIO.load(
                from: url,
                preferredKind: preferredKind
            )
            let resolvedDuration: TimeInterval?
            if let duration {
                resolvedDuration = duration
            } else {
                resolvedDuration = await Self.mediaDuration(
                    of: url,
                    kind: loaded.inferredKind
                )
            }
            return await sendMedia(
                data: loaded.data,
                filename: loaded.filename,
                mimeType: loaded.mimeType,
                kind: loaded.inferredKind,
                duration: resolvedDuration,
                to: peer
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func sendMedia(
        data: Data,
        filename rawFilename: String,
        mimeType: String,
        kind rawKind: ChatMessage.Kind,
        duration suppliedDuration: TimeInterval? = nil,
        to explicitJID: String? = nil,
        messageID explicitMessageID: String? = nil,
        thumbnailData preparedThumbnailData: Data? = nil
    ) async -> String? {
        guard let account,
            let peer = explicitJID ?? selectedConversation?.jid
        else { return nil }
        errorMessage = nil
        if connectionStatus != .connected {
            await reconnect()
        }
        let activityToken = beginMediaSendActivity()
        defer { endMediaSendActivity(activityToken) }
        let id = explicitMessageID ?? UUID().uuidString
        let filename = Self.safeFilename(rawFilename)
        let kind = rawKind.isMedia ? rawKind : .attachment
        let conversation = conversations.first { $0.jid == peer.lowercased() }
        let isGroup = conversation?.isGroup == true
        let encrypted = encryptionEnabled(for: peer)
        var duration = suppliedDuration
        var didInsertPending = false
        var sentID: String?

        do {
            if let value = duration, !value.isFinite || value <= 0 {
                duration = nil
            }
            if duration == nil {
                duration = await Self.mediaDuration(data: data, filename: filename, kind: kind)
            }

            let pending = ChatMessage(
                id: id,
                conversationID: peer,
                senderJID: account.normalizedJID,
                body: Self.mediaTitle(kind: kind, filename: filename),
                direction: .outgoing,
                delivery: .sending,
                security: encrypted ? .omemo : .plaintext,
                kind: kind,
                localFilename: filename,
                mimeType: mimeType,
                duration: duration,
                byteCount: data.count,
                senderDisplayName: isGroup ? conversation?.groupNickname : nil,
                isGroupMessage: isGroup
            )
            upsertMessage(pending)
            didInsertPending = true
            if Self.supportsInlinePreview(kind) {
                await cacheMediaPreview(
                    data: data,
                    messageID: id,
                    filename: filename,
                    kind: kind,
                    mimeType: mimeType,
                    preparedThumbnailData: preparedThumbnailData
                )
            }
            let result = try await uploadAndSendMediaWithRetry(
                data: data,
                filename: filename,
                mimeType: mimeType,
                kind: kind,
                duration: duration,
                to: peer,
                messageID: id,
                encrypted: encrypted,
                isGroup: isGroup
            )
            updateMessage(id: id) {
                $0.delivery = .sent
                $0.remoteAttachmentURL = result.remoteURL
                $0.encryptionFingerprint = result.fingerprint
            }
            sentID = id
        } catch {
            if didInsertPending {
                updateMessage(id: id) { $0.delivery = .failed }
            }
            errorMessage = error.localizedDescription
        }
        schedulePersist()
        syncWatch()
        return sentID
    }

    func canRetryMediaMessage(_ message: ChatMessage) -> Bool {
        message.direction == .outgoing
            && message.delivery == .failed
            && message.kind.isMedia
            && message.remoteAttachmentURL == nil
            && mediaPreviewURLs[message.clientID] != nil
    }

    func retryMediaMessage(_ message: ChatMessage) async {
        guard canRetryMediaMessage(message),
            let localURL = mediaPreviewURLs[message.clientID]
        else { return }
        let activityToken = beginMediaSendActivity()
        defer { endMediaSendActivity(activityToken) }
        errorMessage = nil

        if connectionStatus != .connected {
            await reconnect()
        }

        do {
            let data = try await mediaFileIO.load(
                from: localURL,
                preferredKind: message.kind
            ).data
            updateMessage(id: message.clientID) { $0.delivery = .sending }
            let result = try await uploadAndSendMediaWithRetry(
                data: data,
                filename: message.localFilename ?? localURL.lastPathComponent,
                mimeType: message.mimeType ?? "application/octet-stream",
                kind: message.kind,
                duration: message.duration,
                to: message.conversationID,
                messageID: message.clientID,
                encrypted: message.security == .omemo,
                isGroup: message.isGroupMessage
            )
            updateMessage(id: message.clientID) {
                $0.delivery = .sent
                $0.remoteAttachmentURL = result.remoteURL
                $0.encryptionFingerprint = result.fingerprint
            }
        } catch {
            updateMessage(id: message.clientID) { $0.delivery = .failed }
            errorMessage = error.localizedDescription
        }
        schedulePersist()
        syncWatch()
    }

    func prepareAttachmentDrafts(
        from urls: [URL],
        preferredKind: ChatMessage.Kind? = nil,
        for peerJID: String? = nil
    ) async -> [AttachmentDraft] {
        guard !urls.isEmpty else { return [] }
        let preparationToken = beginMediaPreparationActivity()
        defer { endMediaPreparationActivity(preparationToken) }
        var drafts: [AttachmentDraft] = []
        var lastPreparationError: Error?

        for source in urls.prefix(20) {
            do {
                let staged = try await mediaFileIO.stageAttachmentDraft(from: source)
                let filename = Self.safeFilename(staged.filename)
                let contentType =
                    staged.contentTypeIdentifier.flatMap { UTType($0) }
                    ?? UTType(filenameExtension: source.pathExtension)
                let kind = preferredKind ?? Self.mediaKind(for: contentType, filename: filename)
                let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
                let analysis = await mediaPreviewProcessor.analyze(
                    url: staged.url,
                    kind: kind,
                    mimeType: mimeType
                )
                drafts.append(
                    AttachmentDraft(
                        url: staged.url,
                        filename: filename,
                        mimeType: mimeType,
                        kind: kind,
                        duration: analysis.duration,
                        byteCount: staged.byteCount,
                        thumbnailData: analysis.thumbnailData
                    ))
            } catch {
                lastPreparationError = error
            }
        }
        if drafts.isEmpty, let lastPreparationError {
            errorMessage = lastPreparationError.localizedDescription
        }
        return drafts
    }

    /// Extends the same finite MAM pause across item-provider/iCloud work that
    /// happens before URLs enter `prepareAttachmentDrafts`.
    func withMediaPreparationActivity<T>(
        _ operation: () async -> T
    ) async -> T {
        let token = beginMediaPreparationActivity()
        defer { endMediaPreparationActivity(token) }
        return await operation()
    }

    func sendAttachmentBatch(
        _ drafts: [AttachmentDraft],
        caption rawCaption: String,
        to roomOrPeerJID: String
    ) async -> AttachmentBatchResult {
        guard !drafts.isEmpty else {
            return AttachmentBatchResult(sentCount: 0, failedDrafts: [], captionSent: false)
        }
        let activityToken = beginMediaSendActivity()
        defer { endMediaSendActivity(activityToken) }
        errorMessage = nil

        var firstSentID: String?
        var sentCount = 0
        var failedDrafts: [AttachmentDraft] = []
        for draft in drafts {
            let data: Data
            do {
                data = try await mediaFileIO.load(
                    from: draft.url,
                    preferredKind: draft.kind
                ).data
            } catch {
                errorMessage = "Не удалось прочитать \(draft.filename)."
                failedDrafts.append(draft)
                continue
            }
            let sentID = await sendMedia(
                data: data,
                filename: draft.filename,
                mimeType: draft.mimeType,
                kind: draft.kind,
                duration: draft.duration,
                to: roomOrPeerJID,
                thumbnailData: draft.thumbnailData
            )
            if let sentID {
                if firstSentID == nil { firstSentID = sentID }
                sentCount += 1
                discardAttachmentDrafts([draft])
            } else {
                failedDrafts.append(draft)
            }
        }

        let caption = rawCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        var captionSent = false
        if failedDrafts.isEmpty, !caption.isEmpty {
            let target = firstSentID.flatMap { message(withID: $0, in: roomOrPeerJID) }
            errorMessage = nil
            await sendText(
                caption,
                to: roomOrPeerJID,
                replyingTo: target?.canBeRepliedTo == true ? target : nil
            )
            captionSent = errorMessage == nil
        }
        return AttachmentBatchResult(
            sentCount: sentCount,
            failedDrafts: failedDrafts,
            captionSent: captionSent
        )
    }

    func discardAttachmentDrafts(_ drafts: [AttachmentDraft]) {
        for draft in drafts where draft.isTemporary {
            try? FileManager.default.removeItem(at: draft.url)
        }
    }

    func previewAttachment(_ message: ChatMessage) async {
        do {
            let output: URL
            if let cached = mediaPreviewURLs[message.clientID] {
                output = cached
            } else {
                guard message.remoteAttachmentURL != nil else { return }
                output = try await localAttachmentURL(for: message, directoryName: "LumaPreview")
            }
            previewURL = output
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func mediaPreviewURL(for message: ChatMessage) -> URL? {
        mediaPreviewURLs[message.clientID]
    }

    func mediaThumbnail(for message: ChatMessage) -> Data? {
        mediaThumbnailData[message.clientID]
    }

    func audioWaveform(for message: ChatMessage) -> [Float] {
        audioWaveformSamples[message.clientID] ?? MediaPreviewProcessor.placeholderWaveform
    }

    func isMediaPreviewLoading(_ message: ChatMessage) -> Bool {
        loadingMediaIDs.contains(message.clientID)
    }

    func prepareMediaPreview(_ message: ChatMessage) async {
        guard Self.supportsInlinePreview(message.kind),
            message.remoteAttachmentURL != nil,
            mediaPreviewURLs[message.clientID] == nil,
            loadingMediaIDs.insert(message.clientID).inserted
        else { return }
        defer { loadingMediaIDs.remove(message.clientID) }

        do {
            let output = try await localAttachmentURL(
                for: message, directoryName: "LumaMediaPreviews")
            mediaPreviewURLs[message.clientID] = output
            await analyzeMediaPreview(
                at: output,
                messageID: message.clientID,
                kind: message.kind,
                mimeType: message.mimeType
            )
        } catch {
            // Automatic previews are best-effort. An explicit tap still uses
            // previewAttachment(_:) and presents the actionable error.
        }
    }

    func presentMediaViewer(_ message: ChatMessage) async {
        guard message.kind == .photo || message.kind == .video else { return }

        do {
            let output: URL
            if let cached = mediaPreviewURLs[message.clientID] {
                output = cached
            } else {
                guard message.remoteAttachmentURL != nil else { return }
                loadingMediaIDs.insert(message.clientID)
                defer { loadingMediaIDs.remove(message.clientID) }
                output = try await localAttachmentURL(
                    for: message,
                    directoryName: "LumaMediaPreviews"
                )
                mediaPreviewURLs[message.clientID] = output
                await analyzeMediaPreview(
                    at: output,
                    messageID: message.clientID,
                    kind: message.kind,
                    mimeType: message.mimeType
                )
            }

            audioPlayback.stop()
            NotificationCenter.default.post(
                name: .lumaExclusiveMediaPlayback,
                object: message.clientID
            )
            mediaViewerItem = MediaViewerItem(
                id: message.clientID,
                url: output,
                kind: message.kind,
                title: message.localFilename ?? (message.kind == .photo ? "Фото" : "Видео")
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func closeMediaViewer() {
        mediaViewerItem = nil
    }

    func encryptionEnabled(for jid: String) -> Bool {
        return encryptionPreference(for: jid).resolved(globalEnabled: globalEncryptionEnabled)
    }

    func encryptionPreference(for jid: String) -> EncryptionPreference {
        conversations
            .first(where: { $0.jid == jid.lowercased() })?
            .encryptionPreference ?? .inheritGlobal
    }

    func setGlobalEncryptionEnabled(_ enabled: Bool) {
        globalEncryptionEnabled = enabled
        if let account {
            preferences.setEncryptionEnabled(enabled, for: account.normalizedJID)
        }
    }

    func setTypingIndicatorsEnabled(_ enabled: Bool) {
        typingIndicatorsEnabled = enabled
        xmpp.setChatStatesEnabled(enabled)
        if let account {
            preferences.setChatStatesEnabled(enabled, for: account.normalizedJID)
        }
        if !enabled {
            resetTypingState()
        }
    }

    func typingText(for conversation: Conversation) -> String? {
        let names =
            typingParticipantsByConversation[conversation.jid.lowercased()]
            .map { Array($0.values) } ?? []
        return ChatTypingPolicy.displayText(names: names, isGroup: conversation.isGroup)
    }

    func updateComposerActivity(_ text: String, in conversation: Conversation) {
        let conversationID = conversation.jid.lowercased()
        localTypingPauseTasks[conversationID]?.cancel()
        localTypingPauseTasks[conversationID] = nil
        guard typingIndicatorsEnabled, appIsActive else { return }

        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText else {
            transitionLocalChatState(.paused, in: conversation)
            return
        }

        transitionLocalChatState(.composing, in: conversation)
        localTypingPauseTasks[conversationID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: ChatTypingPolicy.pauseDelayNanoseconds)
            } catch {
                return
            }
            guard let self,
                self.localChatStateByConversation[conversationID] == .composing
            else { return }
            self.transitionLocalChatState(.paused, in: conversation)
            self.localTypingPauseTasks[conversationID] = nil
        }
    }

    func endComposerActivity(in conversation: Conversation) {
        let conversationID = conversation.jid.lowercased()
        localTypingPauseTasks[conversationID]?.cancel()
        localTypingPauseTasks[conversationID] = nil
        transitionLocalChatState(.inactive, in: conversation)
    }

    func toggleReaction(_ emoji: String, on sourceMessage: ChatMessage) async {
        guard let account,
            let message = message(
                withID: sourceMessage.clientID,
                in: sourceMessage.conversationID
            ),
            message.canBeReactedTo,
            let targetID = message.reactionIdentifier,
            let selectedEmoji = MessageReactionPolicy.sanitized([emoji]).first
        else { return }

        let previous = message.reactionEmojis(from: account.normalizedJID)
        var updated = previous
        if let index = updated.firstIndex(of: selectedEmoji) {
            updated.remove(at: index)
        } else {
            updated.append(selectedEmoji)
        }
        updated = MessageReactionPolicy.sanitized(updated)

        let optimisticTimestamp = Date()
        let optimistic = XMPPService.ReactionEnvelope(
            peerJID: message.conversationID,
            senderJID: account.normalizedJID,
            targetID: targetID,
            emojis: updated,
            timestamp: optimisticTimestamp,
            isOutgoing: true,
            isGroupMessage: message.isGroupMessage
        )
        applyReaction(optimistic)

        do {
            try await xmpp.sendReactions(
                to: message.conversationID,
                targetID: targetID,
                emojis: updated,
                reactionMessageID: UUID().uuidString,
                isGroup: message.isGroupMessage
            )
        } catch {
            let rollback = XMPPService.ReactionEnvelope(
                peerJID: message.conversationID,
                senderJID: account.normalizedJID,
                targetID: targetID,
                emojis: previous,
                timestamp: optimisticTimestamp.addingTimeInterval(0.001),
                isOutgoing: true,
                isGroupMessage: message.isGroupMessage
            )
            applyReaction(rollback)
            errorMessage = error.localizedDescription
        }
        schedulePersist()
    }

    func setEncryptionPreference(_ preference: EncryptionPreference, for jid: String) {
        guard let index = conversations.firstIndex(where: { $0.jid == jid.lowercased() }) else {
            return
        }
        conversations[index].encryptionPreference = preference
        schedulePersist()
        syncWatch()
    }

    func avatarData(for jid: String) -> Data? {
        avatarDataByJID[jid.lowercased()]
    }

    func updateOwnAvatar(from sourceData: Data) async {
        guard let account else { return }
        isUpdatingAvatar = true
        defer { isUpdatingAvatar = false }
        do {
            let pngData = try AvatarImageProcessor.pngData(from: sourceData)
            try await xmpp.updateOwnAvatar(pngData: pngData)
            avatarDataByJID[account.normalizedJID] = pngData
            try? await avatarCache.store(pngData, for: account.normalizedJID)
            informationalMessage = "Аватар обновлён."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func devices(for jid: String) -> [OMEMODevice] {
        xmpp.devices(for: jid)
    }

    func setDeviceVerified(_ verified: Bool, jid: String, deviceID: Int32) {
        xmpp.setDeviceVerified(verified, jid: jid, deviceID: deviceID)
        objectWillChange.send()
    }

    func refreshServerInformation() async {
        do {
            serverInformation = try await xmpp.fetchServerInformation()
        } catch {
            // The screen shows its own error state; keep any previously loaded
            // snapshot rather than clearing it on a transient refresh failure.
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func beginMediaSendActivity() -> UUID {
        let token = mediaSendActivity.begin()
        isSendingAttachment = mediaSendActivity.isActive
        updateArchiveSyncSuspensionForMedia()
        return token
    }

    private func endMediaSendActivity(_ token: UUID) {
        mediaSendActivity.end(token)
        isSendingAttachment = mediaSendActivity.isActive
        updateArchiveSyncSuspensionForMedia()
    }

    private func resetMediaSendActivity() {
        mediaSendActivity.reset()
        mediaPreparationTokens.removeAll(keepingCapacity: false)
        videoNoteCaptureIsActive = false
        isSendingAttachment = false
        updateArchiveSyncSuspensionForMedia()
    }

    private func beginMediaPreparationActivity() -> UUID {
        let token = UUID()
        mediaPreparationTokens.insert(token)
        updateArchiveSyncSuspensionForMedia()
        return token
    }

    private func endMediaPreparationActivity(_ token: UUID) {
        mediaPreparationTokens.remove(token)
        updateArchiveSyncSuspensionForMedia()
    }

    private func updateArchiveSyncSuspensionForMedia() {
        let shouldSuspend =
            videoNoteCaptureIsActive
            || mediaSendActivity.isActive
            || !mediaPreparationTokens.isEmpty
        guard shouldSuspend != archiveSyncIsSuspendedForMedia else { return }
        archiveSyncIsSuspendedForMedia = shouldSuspend
        xmpp.setArchiveSyncSuspendedForMediaWork(shouldSuspend)
    }

    private func uploadAndSendMediaWithRetry(
        data: Data,
        filename: String,
        mimeType: String,
        kind: ChatMessage.Kind,
        duration: TimeInterval?,
        to recipient: String,
        messageID: String,
        encrypted: Bool,
        isGroup: Bool
    ) async throws -> XMPPService.MediaSendResult {
        let maximumAttempts = 2
        for attempt in 1...maximumAttempts {
            do {
                return try await xmpp.uploadAndSendMedia(
                    data: data,
                    filename: filename,
                    mimeType: mimeType,
                    kind: kind,
                    duration: duration,
                    to: recipient,
                    messageID: messageID,
                    encrypted: encrypted,
                    isGroup: isGroup
                )
            } catch {
                guard attempt < maximumAttempts,
                    Self.isRetryableMediaSendError(error)
                else { throw error }
                if connectionStatus != .connected {
                    await reconnect()
                }
                try await Task.sleep(nanoseconds: 600_000_000)
            }
        }
        throw LumaXMPPError.uploadFailed(statusCode: nil)
    }

    private static func isRetryableMediaSendError(_ error: Error) -> Bool {
        guard let error = error as? LumaXMPPError else { return false }
        switch error {
        case .notConnected, .connection, .uploadDiscoveryFailed,
            .uploadSlotFailed, .uploadTransportFailed:
            return true
        case .uploadFailed(let statusCode):
            guard let statusCode else { return true }
            return statusCode == 408 || statusCode == 429 || statusCode >= 500
        default:
            return false
        }
    }

    private func requestCallPermissions(includeVideo: Bool) async -> Bool {
        guard await Self.requestCaptureAccess(for: .audio) else {
            errorMessage = "Разрешите Luma доступ к микрофону в системных настройках."
            return false
        }
        if includeVideo {
            guard await Self.requestCaptureAccess(for: .video) else {
                errorMessage = "Разрешите Luma доступ к камере в системных настройках."
                return false
            }
        }
        return true
    }

    private static func requestCaptureAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func consume(_ event: XMPPService.Event) {
        switch event {
        case .connection(let status):
            connectionStatus = status
            if status == .connected {
                if let account {
                    xmpp.fetchAvatar(for: account.normalizedJID)
                }
                conversations.filter { !$0.isGroup }.forEach {
                    xmpp.prepareDirectChat(with: $0.jid)
                    xmpp.fetchAvatar(for: $0.jid)
                }
                for room in conversations where room.isGroup && room.shouldAutojoin {
                    Task { await joinGroup(jid: room.jid) }
                }
            } else if case .disconnected = status {
                // A transport disconnect is a hard boundary for MAM. Keep the
                // UI from displaying a stale spinner even if the archive
                // completion event was overtaken by a socket state change.
                isArchiveSyncing = false
                isLoadingOlderHistory = false
                for index in conversations.indices where conversations[index].isGroup {
                    conversations[index].isGroupJoined = false
                    conversations[index].occupantCount = 0
                }
                resetTypingState()
            }
        case .rosterItem(let jid, let name):
            let normalized = jid.lowercased()
            rosterContactJIDs.insert(normalized)
            upsertConversation(jid: normalized, name: name)
        case .rosterRemoved(let jid):
            // Keep the chat history but remove it from the server-backed
            // contacts screen as soon as Prosody confirms the roster push.
            rosterContactJIDs.remove(jid.lowercased())
        case .presence(let jid, let online):
            if let index = conversations.firstIndex(where: { $0.jid == jid.lowercased() }) {
                conversations[index].isOnline = online
            }
        case .message(let envelope):
            consumeMessage(envelope)
        case .retraction(let envelope):
            applyRetraction(envelope)
        case .reaction(let envelope):
            applyReaction(envelope)
        case .chatState(let envelope):
            if typingIndicatorsEnabled {
                applyRemoteChatState(envelope)
            }
            return
        case .groupMessageEcho(let roomJID, let messageID, let stanzaID, let senderJID):
            if let index = messageIndex(id: messageID, conversationID: roomJID)
                ?? messageIndex(referenceID: stanzaID, conversationID: roomJID)
            {
                messages[index].stanzaID = stanzaID
                messages[index].senderJID = senderJID
                messageIndexByStanzaKey[
                    Self.localDeletionKey(
                        messageID: stanzaID,
                        conversationID: roomJID
                    )] = index
                if messages[index].delivery == .sending {
                    messages[index].delivery = .sent
                }
                applyPendingReactions(for: messages[index])
            }
        case .roomState(let envelope):
            upsertGroupConversation(
                jid: envelope.roomJID,
                name: nil,
                nickname: envelope.nickname,
                shouldAutojoin: envelope.joined
            )
            if let index = conversations.firstIndex(where: {
                $0.jid == envelope.roomJID.lowercased()
            }) {
                conversations[index].isGroupJoined = envelope.joined
                conversations[index].occupantCount = envelope.occupantCount
            }
        case .roomInvitation(let invitation):
            let jid = invitation.roomJID.lowercased()
            upsertGroupConversation(
                jid: jid,
                name: nil,
                nickname: defaultGroupNickname,
                shouldAutojoin: false,
                invitedBy: invitation.inviterJID
            )
            if let password = invitation.password {
                pendingRoomPasswords[jid] = password
            }
            if let reason = invitation.reason, !reason.isEmpty {
                informationalMessage = "Приглашение в \(jid): \(reason)"
            } else {
                informationalMessage = "Получено приглашение в групповой чат \(jid)."
            }
        case .avatar(let jid, let data):
            let normalized = jid.lowercased()
            avatarDataByJID[normalized] = data
            Task { try? await avatarCache.store(data, for: normalized) }
        case .delivered(let messageID):
            let targetID = correctionReceiptTargets.removeValue(forKey: messageID) ?? messageID
            updateMessage(id: targetID) { $0.delivery = .delivered }
        case .omemo(let ready, let fingerprint):
            isOMEMOReady = ready
            ownFingerprint = fingerprint
        case .archiveBatch(let mutations):
            applyArchiveBatch(mutations)
            return
        case .archiveSyncing(let syncing):
            isArchiveSyncing = syncing
        case .archiveSyncCompleted(let checkpoint):
            lastSuccessfulMAMSync = checkpoint.timestamp
            lastSuccessfulMAMCursor = checkpoint.cursor
            if let account {
                mamCheckpoints[.account(account.normalizedJID)] = MAMArchiveCheckpoint(
                    timestamp: checkpoint.timestamp,
                    cursor: checkpoint.cursor
                )
            }
            // Синхронно форсируем persist, чтобы checkpoint не потерялся
            persistTask?.cancel()
            persistTask = nil
            Task { @MainActor [weak self] in
                guard let self, let store = self.store else { return }
                try? store.save(
                    locallyDeletedMessageIDs: self.locallyDeletedMessageIDs,
                    rosterContactJIDs: self.rosterContactJIDs,
                    lastSuccessfulMAMSync: self.lastSuccessfulMAMSync,
                    lastSuccessfulMAMCursor: self.lastSuccessfulMAMCursor,
                    mamCheckpoints: self.mamCheckpoints
                )
            }
        case .mucArchiveSyncCompleted(let archiveKey, let checkpoint):
            mamCheckpoints[archiveKey] = checkpoint
            schedulePersist()
        case .call(let call):
            activeCall = call
        case .callHistory(let entry):
            recordCallHistory(entry)
        case .callError(let message):
            errorMessage = message
        case .recoverableError(let message):
            informationalMessage = message
        }
        if !isApplyingArchiveBatch {
            sortConversations()
        }
        if !isArchiveSyncing {
            schedulePersist()
            syncWatch()
        }
    }

    private func applyArchiveBatch(_ mutations: [XMPPService.ArchiveMutation]) {
        guard !mutations.isEmpty else { return }
        let selectedConversationWasMutated =
            selectedConversationID.map { selectedID in
                mutations.contains { mutation in
                    switch mutation {
                    case .message(let envelope):
                        return envelope.peerJID.lowercased() == selectedID
                    case .retraction(let envelope):
                        return envelope.peerJID.lowercased() == selectedID
                    case .reaction(let envelope):
                        return envelope.peerJID.lowercased() == selectedID
                    }
                }
            } ?? false
        isApplyingArchiveBatch = true
        for mutation in mutations {
            switch mutation {
            case .message(let envelope):
                consumeMessage(envelope)
            case .retraction(let envelope):
                applyRetraction(envelope)
            case .reaction(let envelope):
                applyReaction(envelope)
            }
        }
        sortConversations()
        isApplyingArchiveBatch = false
        if selectedConversationWasMutated {
            selectedMessagesCacheConversationID = nil
            selectedTimelineEntriesCacheConversationID = nil
        }
        // Publish only after the complete pass is internally consistent. This
        // prevents SwiftUI from reading half-merged arrays while MAM is busy.
        objectWillChange.send()
    }

    private func resetArchiveBatchState() {
        isApplyingArchiveBatch = false
    }

    private func consumeMessage(_ envelope: XMPPService.MessageEnvelope) {
        if !envelope.isGroupMessage {
            upsertConversation(jid: envelope.peerJID, name: nil)
        }
        if let stanzaID = envelope.stanzaID,
            messageIndex(referenceID: stanzaID, conversationID: envelope.peerJID) != nil
        {
            return  // уже есть это сообщение
        }
        if let originID = envelope.originID,
           messageIndex(originID: originID, conversationID: envelope.peerJID) != nil {
            mergeServerIdentity(from: envelope, matchingOriginID: originID)
            return
        }
        if envelope.isGroupMessage {
            upsertGroupConversation(
                jid: envelope.peerJID,
                name: nil,
                nickname: nil,
                shouldAutojoin: true
            )
        }
        let deletionKey = Self.localDeletionKey(
            messageID: envelope.id,
            conversationID: envelope.peerJID
        )
        let correctionWasDeleted =
            envelope.correctionTargetID.map {
                locallyDeletedMessageIDs.contains(
                    Self.localDeletionKey(
                        messageID: $0,
                        conversationID: envelope.peerJID
                    ))
            } ?? false
        guard !locallyDeletedMessageIDs.contains(deletionKey),
            !correctionWasDeleted
        else { return }
        if envelope.correctionTargetID != nil {
            consumeCorrection(envelope)
            return
        }

        let message = ChatMessage(
            id: envelope.id,
            conversationID: envelope.peerJID,
            senderJID: envelope.senderJID,
            body: envelope.body,
            timestamp: envelope.timestamp,
            direction: envelope.isOutgoing ? .outgoing : .incoming,
            delivery: envelope.isOutgoing ? .sent : .delivered,
            security: envelope.security,
            kind: envelope.kind,
            remoteAttachmentURL: envelope.remoteAttachmentURL,
            localFilename: envelope.localFilename,
            mimeType: envelope.mimeType,
            duration: envelope.duration,
            byteCount: envelope.byteCount,
            encryptionFingerprint: envelope.fingerprint,
            replyToID: envelope.replyToID,
            replyToJID: envelope.replyToJID,
            replyPreview: envelope.replyPreview,
            originID: envelope.originID,
            stanzaID: envelope.stanzaID,
            senderDisplayName: envelope.senderDisplayName,
            isGroupMessage: envelope.isGroupMessage
        )
        let inserted = upsertMessage(
            message,
            incrementUnread: envelope.isArchived ? false : nil
        )
        let pendingKey = Self.localDeletionKey(
            messageID: message.clientID,
            conversationID: message.conversationID
        )
        if let correction = pendingCorrections.removeValue(forKey: pendingKey) {
            consumeCorrection(correction)
        }
        if let retraction = pendingRetractions.removeValue(forKey: pendingKey) {
            applyRetraction(retraction)
        }
        applyPendingReactions(for: message)
        if !envelope.isArchived,
            NotificationPolicy.shouldPresentMessage(
                inserted: inserted,
                isOutgoing: envelope.isOutgoing,
                appIsActive: appIsActive,
                selectedConversationID: selectedConversationID,
                conversationID: envelope.peerJID
            )
        {
            let notificationMessage =
                self.message(
                    withID: envelope.id,
                    in: envelope.peerJID
                ) ?? message
            notifications.showIncomingMessage(
                id: envelope.id,
                sender: envelope.senderDisplayName ?? conversationName(for: envelope.peerJID),
                body: notificationMessage.previewText,
                conversationID: envelope.peerJID
            )
        }
    }
    
    private func mergeServerIdentity(
        from envelope: XMPPService.MessageEnvelope,
        matchingOriginID originID: String
    ) {
        guard let index = messageIndex(
            originID: originID,
            conversationID: envelope.peerJID
        ) else { return }
        if messages[index].stanzaID == nil {
            messages[index].stanzaID = envelope.stanzaID
        }
        if messages[index].delivery == .sending {
            messages[index].delivery = .sent
        }
        rebuildMessageIndex()
        schedulePersist()
    }

    private func recordCallHistory(_ entry: CallHistoryEntry) {
        guard let account else { return }
        let direction: ChatMessage.Direction =
            entry.direction == .outgoing
            ? .outgoing
            : .incoming
        let metadata = CallHistoryMetadata(
            isVideo: entry.isVideo,
            outcome: entry.outcome
        )
        let message = ChatMessage(
            id: entry.id,
            conversationID: entry.peerJID,
            senderJID: direction == .outgoing ? account.normalizedJID : entry.peerJID,
            body: entry.isVideo ? "Видеозвонок" : "Аудиозвонок",
            timestamp: entry.startedAt,
            direction: direction,
            delivery: direction == .outgoing ? .sent : .delivered,
            security: .plaintext,
            kind: .system,
            duration: entry.duration,
            callHistory: metadata
        )
        let isUnreadMissedCall =
            direction == .incoming
            && entry.outcome == .missed
            && selectedConversationID != entry.peerJID.lowercased()
        _ = upsertMessage(message, incrementUnread: isUnreadMissedCall)
    }

    private func upsertConversation(jid: String, name: String?) {
        let normalized = jid.lowercased()
        if let index = conversations.firstIndex(where: { $0.jid == normalized }) {
            if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversations[index].displayName = name
            }
        } else {
            let conversation = Conversation(jid: normalized, displayName: name)
            store?.context.insert(conversation)
            conversations.append(conversation)
        }
        if conversations.first(where: { $0.jid == normalized })?.isGroup != true {
            if !isApplyingArchiveBatch {
                xmpp.prepareDirectChat(with: normalized)
            }
            loadCachedAvatarIfNeeded(for: normalized)
        }
        if !isApplyingArchiveBatch {
            sortConversations()
        }
    }

    private func upsertGroupConversation(
        jid: String,
        name: String?,
        nickname: String?,
        shouldAutojoin: Bool,
        invitedBy: String? = nil
    ) {
        let normalized = jid.lowercased()
        let fallbackName = normalized.split(separator: "@").first.map(String.init) ?? normalized
        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialDisplayName: String
        if let resolvedName, !resolvedName.isEmpty {
            initialDisplayName = resolvedName
        } else {
            initialDisplayName = fallbackName
        }
        if let index = conversations.firstIndex(where: { $0.jid == normalized }) {
            conversations[index].kind = .group
            if let resolvedName, !resolvedName.isEmpty {
                conversations[index].displayName = resolvedName
            } else if conversations[index].displayName == normalized {
                conversations[index].displayName = fallbackName
            }
            if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversations[index].groupNickname = nickname
            }
            conversations[index].shouldAutojoin =
                conversations[index].shouldAutojoin || shouldAutojoin
            if let invitedBy { conversations[index].invitedBy = invitedBy }
        } else {
            let conversation = Conversation(
                jid: normalized,
                displayName: initialDisplayName,
                encryptionPreference: .inheritGlobal,
                kind: .group,
                groupNickname: nickname,
                shouldAutojoin: shouldAutojoin,
                invitedBy: invitedBy
            )
            store?.context.insert(conversation)
            conversations.append(conversation)
        }
        if !isApplyingArchiveBatch {
            sortConversations()
        }
    }

    private var defaultGroupNickname: String {
        if let displayName = account?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            !displayName.isEmpty
        {
            return displayName
        }
        return account?.normalizedJID.split(separator: "@").first.map(String.init) ?? "Luma"
    }

    private func consumeCorrection(_ envelope: XMPPService.MessageEnvelope) {
        guard let targetID = envelope.correctionTargetID,
            !locallyDeletedMessageIDs.contains(
                Self.localDeletionKey(
                    messageID: targetID,
                    conversationID: envelope.peerJID
                )),
            envelope.kind == .text,
            envelope.security != .decryptionFailed
        else { return }

        guard
            let index = messageIndex(
                id: targetID,
                conversationID: envelope.peerJID
            )
        else {
            let pendingKey = Self.localDeletionKey(
                messageID: targetID,
                conversationID: envelope.peerJID
            )
            pendingCorrections[pendingKey] = envelope
            if pendingCorrections.count > 100, let key = pendingCorrections.keys.first {
                pendingCorrections.removeValue(forKey: key)
            }
            return
        }

        let original = messages[index]
        guard !original.isRetracted,
            original.kind == .text,
            original.conversationID == envelope.peerJID.lowercased(),
            original.senderJID == envelope.senderJID.lowercased(),
            original.security == envelope.security,
            original.editedAt == nil || envelope.timestamp >= original.editedAt!
        else { return }

        messages[index].body = envelope.body
        messages[index].editedAt = envelope.timestamp
        messages[index].security = envelope.security
        messages[index].encryptionFingerprint = envelope.fingerprint
        if envelope.isOutgoing {
            messages[index].delivery = .sent
        }
        updateConversationPreview(for: messages[index], incrementUnread: false)
    }

    private func applyReaction(_ envelope: XMPPService.ReactionEnvelope) {
        let conversationID = envelope.peerJID.lowercased()
        let senderJID = envelope.senderJID.lowercased()
        if !envelope.isGroupMessage {
            var allowedSenders: Set<String> = [
                MessageReactionPolicy.bareJID(conversationID)
            ]
            if let account {
                allowedSenders.insert(MessageReactionPolicy.bareJID(account.normalizedJID))
            }
            guard allowedSenders.contains(MessageReactionPolicy.bareJID(senderJID)) else { return }
        }

        guard
            let index = messageIndex(
                referenceID: envelope.targetID,
                conversationID: conversationID
            )
        else {
            let key = pendingReactionKey(envelope)
            if let previous = pendingReactions[key],
                previous.timestamp > envelope.timestamp
            {
                return
            }
            pendingReactions[key] = envelope
            if pendingReactions.count > 200,
                let staleKey = pendingReactions.min(by: {
                    $0.value.timestamp < $1.value.timestamp
                })?.key
            {
                pendingReactions.removeValue(forKey: staleKey)
            }
            return
        }

        guard !messages[index].isRetracted else { return }
        let updatedMessage = messages[index]
        let existingIndex = updatedMessage.reactions.firstIndex { reaction in
            reactionSenderMatches(
                reaction.senderJID,
                senderJID,
                isGroup: envelope.isGroupMessage
            )
        }
        if let existingIndex,
            updatedMessage.reactions[existingIndex].updatedAt > envelope.timestamp
        {
            return
        }

        let emojis = MessageReactionPolicy.sanitized(envelope.emojis)
        if let existingIndex {
            if emojis.isEmpty {
                updatedMessage.reactions.remove(at: existingIndex)
            } else {
                updatedMessage.reactions[existingIndex] = MessageReaction(
                    senderJID: senderJID,
                    emojis: emojis,
                    updatedAt: envelope.timestamp
                )
            }
        } else if !emojis.isEmpty {
            updatedMessage.reactions.append(
                MessageReaction(
                    senderJID: senderJID,
                    emojis: emojis,
                    updatedAt: envelope.timestamp
                ))
        } else {
            return
        }
        updatedMessage.reactions.sort { $0.senderJID < $1.senderJID }
        messages[index] = updatedMessage
    }

    private func applyPendingReactions(for message: ChatMessage) {
        let identifiers = Set([message.clientID, message.stanzaID].compactMap { $0 })
        guard !identifiers.isEmpty else { return }
        let matches = pendingReactions.filter { _, envelope in
            envelope.peerJID.lowercased() == message.conversationID
                && identifiers.contains(envelope.targetID)
        }
        for (key, envelope) in matches {
            pendingReactions.removeValue(forKey: key)
            applyReaction(envelope)
        }
    }

    private func pendingReactionKey(_ envelope: XMPPService.ReactionEnvelope) -> String {
        [
            envelope.peerJID.lowercased(),
            envelope.targetID,
            envelope.senderJID.lowercased(),
        ].joined(separator: "|")
    }

    private func reactionSenderMatches(
        _ lhs: String,
        _ rhs: String,
        isGroup: Bool
    ) -> Bool {
        if isGroup { return lhs.lowercased() == rhs.lowercased() }
        return MessageReactionPolicy.bareJID(lhs) == MessageReactionPolicy.bareJID(rhs)
    }

    private func applyRemoteChatState(_ envelope: XMPPService.ChatStateEnvelope) {
        let conversationID = envelope.peerJID.lowercased()
        let senderKey =
            envelope.isGroupMessage
            ? envelope.senderJID.lowercased()
            : MessageReactionPolicy.bareJID(envelope.senderJID)
        let expiryKey = "\(conversationID)|\(senderKey)"
        remoteTypingExpiryTasks[expiryKey]?.cancel()
        remoteTypingExpiryTasks[expiryKey] = nil

        guard envelope.state == .composing else {
            removeRemoteTypingParticipant(
                conversationID: conversationID,
                senderKey: senderKey
            )
            return
        }

        var participants = typingParticipantsByConversation[conversationID] ?? [:]
        participants[senderKey] =
            envelope.senderDisplayName
            ?? displayName(for: envelope.senderJID)
        typingParticipantsByConversation[conversationID] = participants
        remoteTypingExpiryTasks[expiryKey] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: ChatTypingPolicy.remoteExpiryNanoseconds)
            } catch {
                return
            }
            self?.removeRemoteTypingParticipant(
                conversationID: conversationID,
                senderKey: senderKey
            )
            self?.remoteTypingExpiryTasks[expiryKey] = nil
        }
    }

    private func removeRemoteTypingParticipant(
        conversationID: String,
        senderKey: String
    ) {
        guard var participants = typingParticipantsByConversation[conversationID] else { return }
        participants.removeValue(forKey: senderKey)
        if participants.isEmpty {
            typingParticipantsByConversation.removeValue(forKey: conversationID)
        } else {
            typingParticipantsByConversation[conversationID] = participants
        }
    }

    private func transitionLocalChatState(
        _ state: ChatTypingState,
        in conversation: Conversation
    ) {
        guard typingIndicatorsEnabled, connectionStatus == .connected else { return }
        let conversationID = conversation.jid.lowercased()
        let previous = localChatStateByConversation[conversationID]
        if state == .paused, previous != .composing { return }
        if state == .inactive, previous == nil { return }
        guard previous != state else { return }
        localChatStateByConversation[conversationID] = state
        Task { [weak self] in
            guard let self else { return }
            try? await self.xmpp.sendChatState(
                state,
                to: conversation.jid,
                isGroup: conversation.isGroup
            )
        }
    }

    private func resetTypingState() {
        localTypingPauseTasks.values.forEach { $0.cancel() }
        remoteTypingExpiryTasks.values.forEach { $0.cancel() }
        localTypingPauseTasks.removeAll(keepingCapacity: false)
        remoteTypingExpiryTasks.removeAll(keepingCapacity: false)
        localChatStateByConversation.removeAll(keepingCapacity: false)
        typingParticipantsByConversation.removeAll(keepingCapacity: false)
    }

    private func applyRetraction(_ envelope: XMPPService.RetractionEnvelope) {
        guard
            !locallyDeletedMessageIDs.contains(
                Self.localDeletionKey(
                    messageID: envelope.targetID,
                    conversationID: envelope.peerJID
                ))
        else { return }
        guard
            let index = messageIndex(
                id: envelope.targetID,
                conversationID: envelope.peerJID
            )
        else {
            let pendingKey = Self.localDeletionKey(
                messageID: envelope.targetID,
                conversationID: envelope.peerJID
            )
            pendingRetractions[pendingKey] = envelope
            if pendingRetractions.count > 100, let staleID = pendingRetractions.keys.first {
                pendingRetractions.removeValue(forKey: staleID)
            }
            return
        }

        let original = messages[index]
        guard original.conversationID == envelope.peerJID.lowercased(),
            original.senderJID == envelope.senderJID.lowercased(),
            original.retractedAt == nil || envelope.timestamp >= original.retractedAt!
        else { return }

        removeCachedMedia(for: original.clientID)
        messages[index].body = "Сообщение удалено"
        messages[index].kind = .system
        messages[index].remoteAttachmentURL = nil
        messages[index].localFilename = nil
        messages[index].mimeType = nil
        messages[index].duration = nil
        messages[index].byteCount = nil
        messages[index].editedAt = nil
        messages[index].replyToID = nil
        messages[index].replyToJID = nil
        messages[index].replyPreview = nil
        messages[index].forwardedFrom = nil
        messages[index].callHistory = nil
        messages[index].reactions = []
        messages[index].retractedAt = envelope.timestamp
        if envelope.isOutgoing, messages[index].delivery == .sending {
            messages[index].delivery = .sent
        }
        pendingCorrections.removeValue(
            forKey: Self.localDeletionKey(
                messageID: original.clientID,
                conversationID: original.conversationID
            ))
        updateConversationPreview(for: messages[index], incrementUnread: false)
    }

    @discardableResult
    private func upsertMessage(
        _ message: ChatMessage,
        incrementUnread unreadOverride: Bool? = nil
    ) -> Bool {
        guard
            !locallyDeletedMessageIDs.contains(
                Self.localDeletionKey(
                    messageID: message.clientID,
                    conversationID: message.conversationID
                ))
        else { return false }
        upsertConversation(jid: message.conversationID, name: nil)
        if let index = messageIndex(
            id: message.clientID,
            conversationID: message.conversationID
        ) {
            let previous = messages[index]
            if previous.isRetracted {
                if message.delivery == .delivered {
                    messages[index].delivery = .delivered
                }
                updateConversationPreview(for: messages[index], incrementUnread: false)
                return false
            }
            let merged = message
            if previous.direction == .outgoing && message.direction == .outgoing {
                merged.localFilename = previous.localFilename ?? message.localFilename
                merged.mimeType = previous.mimeType ?? message.mimeType
                merged.duration = previous.duration ?? message.duration
                merged.byteCount = previous.byteCount ?? message.byteCount
                if previous.delivery == .delivered {
                    merged.delivery = .delivered
                }
            }
            merged.replyToID = message.replyToID ?? previous.replyToID
            merged.replyToJID = message.replyToJID ?? previous.replyToJID
            merged.replyPreview = message.replyPreview ?? previous.replyPreview
            merged.forwardedFrom = message.forwardedFrom ?? previous.forwardedFrom
            merged.stanzaID = message.stanzaID ?? previous.stanzaID
            merged.senderDisplayName = message.senderDisplayName ?? previous.senderDisplayName
            merged.isGroupMessage = message.isGroupMessage || previous.isGroupMessage
            merged.callHistory = message.callHistory ?? previous.callHistory
            if message.reactions.isEmpty {
                merged.reactions = previous.reactions
            }
            if let editedAt = previous.editedAt,
                message.editedAt == nil || editedAt > message.editedAt!
            {
                merged.body = previous.body
                merged.editedAt = editedAt
                merged.security = previous.security
                merged.encryptionFingerprint = previous.encryptionFingerprint
            }
            if message.security == .decryptionFailed,
               previous.security != .decryptionFailed,
               !previous.body.isEmpty
            {
                // Our own outgoing message was rendered optimistically with the
                // text the user typed. Its server echo (carbon or MAM) cannot
                // be decrypted back (no encrypt-to-self key, or a consumed
                // session), so keep the original content instead of replacing
                // it with a "failed to decrypt" placeholder.
                merged.body = previous.body
                merged.security = previous.security
                merged.encryptionFingerprint = previous.encryptionFingerprint
                merged.kind = previous.kind
                merged.remoteAttachmentURL = previous.remoteAttachmentURL
                merged.localFilename = previous.localFilename
                merged.mimeType = previous.mimeType
                merged.duration = previous.duration
                merged.byteCount = previous.byteCount
            }
            messages[index] = merged
            if previous !== merged {
                // `merged` is the freshly-created incoming message; replace the
                // previously managed object with it so SwiftData does not keep
                // an orphaned duplicate of the same clientID.
                store?.context.delete(previous)
                store?.context.insert(merged)
            }
            if let stanzaID = merged.stanzaID {
                messageIndexByStanzaKey[
                    Self.localDeletionKey(
                        messageID: stanzaID,
                        conversationID: merged.conversationID
                    )] = index
            }
            if let originID = merged.originID {
                messageIndexByOriginKey[
                    Self.localDeletionKey(
                        messageID: originID,
                        conversationID: merged.conversationID
                    )] = index
            }
            updateConversationPreview(for: merged, incrementUnread: false)
            return false
        }
        store?.context.insert(message)
        messages.append(message)
        let insertedIndex = messages.index(before: messages.endIndex)
        messageIndexByStorageKey[
            Self.localDeletionKey(
                messageID: message.clientID,
                conversationID: message.conversationID
            )] = insertedIndex
        if firstMessageIndexByID[message.clientID] == nil {
            firstMessageIndexByID[message.clientID] = insertedIndex
        }
        if let stanzaID = message.stanzaID {
            messageIndexByStanzaKey[
                Self.localDeletionKey(
                    messageID: stanzaID,
                    conversationID: message.conversationID
                )] = insertedIndex
        }
        if let originID = message.originID {
            messageIndexByOriginKey[
                Self.localDeletionKey(
                    messageID: originID,
                    conversationID: message.conversationID
                )] = insertedIndex
        }
        let shouldIncrement =
            unreadOverride
            ?? (message.direction == .incoming && selectedConversationID != message.conversationID)
        updateConversationPreview(for: message, incrementUnread: shouldIncrement)
        return true
    }

    private func updateMessage(id: String, mutation: (inout ChatMessage) -> Void) {
        guard let index = firstMessageIndexByID[id],
            messages.indices.contains(index),
            messages[index].clientID == id
        else { return }
        mutation(&messages[index])
        updateConversationPreview(for: messages[index], incrementUnread: false)
    }

    private func updateConversationPreview(for message: ChatMessage, incrementUnread: Bool) {
        guard let index = conversations.firstIndex(where: { $0.jid == message.conversationID })
        else { return }
        if message.timestamp >= conversations[index].lastActivity {
            conversations[index].lastActivity = message.timestamp
            conversations[index].lastMessage = message.previewText
        }
        if incrementUnread {
            conversations[index].unreadCount += 1
        }
        if !isApplyingArchiveBatch {
            sortConversations()
        }
    }

    private func rebuildConversationPreview(for conversationID: String) {
        guard let index = conversations.firstIndex(where: { $0.jid == conversationID }) else {
            return
        }
        let latest =
            messages
            .filter { $0.conversationID == conversationID }
            .max { lhs, rhs in
                if lhs.timestamp == rhs.timestamp { return lhs.clientID < rhs.clientID }
                return lhs.timestamp < rhs.timestamp
            }
        conversations[index].lastActivity = latest?.timestamp ?? .distantPast
        conversations[index].lastMessage = latest?.previewText ?? ""
        sortConversations()
    }

    private func conversationName(for jid: String) -> String {
        conversations.first(where: { $0.jid == jid.lowercased() })?.displayName ?? jid
    }

    private func sortConversations() {
        conversations.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                == .orderedAscending
        }
    }

    private func messageIndex(id: String, conversationID: String) -> Int? {
        let normalizedConversationID = conversationID.lowercased()
        let key = Self.localDeletionKey(
            messageID: id,
            conversationID: normalizedConversationID
        )
        guard let index = messageIndexByStorageKey[key] else { return nil }
        if messages.indices.contains(index),
            messages[index].clientID == id,
            messages[index].conversationID == normalizedConversationID
        {
            return index
        }
        rebuildMessageIndex()
        return messageIndexByStorageKey[key]
    }

    private func messageIndex(referenceID: String, conversationID: String) -> Int? {
        if let directIndex = messageIndex(id: referenceID, conversationID: conversationID) {
            return directIndex
        }
        let normalizedConversationID = conversationID.lowercased()
        let key = Self.localDeletionKey(
            messageID: referenceID,
            conversationID: normalizedConversationID
        )
        guard let index = messageIndexByStanzaKey[key] else { return nil }
        if messages.indices.contains(index),
            messages[index].conversationID == normalizedConversationID,
            messages[index].stanzaID == referenceID
        {
            return index
        }
        // Only rebuild when the key exists but points at a stale entry. A
        // genuine miss is expected during archive catch-up for every new
        // stanza-id and must not trigger an O(n) rebuild per message.
        rebuildMessageIndex()
        return messageIndexByStanzaKey[key]
    }

    private func messageIndex(originID: String, conversationID: String) -> Int? {
        let normalizedConversationID = conversationID.lowercased()
        let key = Self.localDeletionKey(
            messageID: originID,
            conversationID: normalizedConversationID
        )
        guard let index = messageIndexByOriginKey[key] else { return nil }
        if messages.indices.contains(index),
            messages[index].conversationID == normalizedConversationID,
            messages[index].originID == originID
        {
            return index
        }
        rebuildMessageIndex()
        return messageIndexByOriginKey[key]
    }

    private func rebuildMessageIndex() {
        messageIndexByStorageKey.removeAll(keepingCapacity: true)
        messageIndexByStanzaKey.removeAll(keepingCapacity: true)
        messageIndexByOriginKey.removeAll(keepingCapacity: true)
        firstMessageIndexByID.removeAll(keepingCapacity: true)
        for (index, message) in messages.enumerated() {
            let key = Self.localDeletionKey(
                messageID: message.clientID,
                conversationID: message.conversationID
            )
            if messageIndexByStorageKey[key] == nil {
                messageIndexByStorageKey[key] = index
            }
            if firstMessageIndexByID[message.clientID] == nil {
                firstMessageIndexByID[message.clientID] = index
            }
            if let stanzaID = message.stanzaID {
                let stanzaKey = Self.localDeletionKey(
                    messageID: stanzaID,
                    conversationID: message.conversationID
                )
                if messageIndexByStanzaKey[stanzaKey] == nil {
                    messageIndexByStanzaKey[stanzaKey] = index
                }
            }
            if let originID = message.originID {
                let originKey = Self.localDeletionKey(
                    messageID: originID,
                    conversationID: message.conversationID
                )
                if messageIndexByOriginKey[originKey] == nil {
                    messageIndexByOriginKey[originKey] = index
                }
            }
        }
    }

    private func loadArchive(for jid: String) async {
        resetArchiveBatchState()
        resetMediaPreviews()
        guard let store = try? ArchiveStore(accountJID: jid) else {
            self.store = nil
            return
        }
        self.store = store
        let snapshot = store.load()
        conversations = snapshot.conversations.map { conversation in
            if conversation.isGroup {
                conversation.isGroupJoined = false
                conversation.occupantCount = 0
            }
            return conversation
        }
        rosterContactJIDs = Set(snapshot.rosterContactJIDs.map { $0.lowercased() })
        locallyDeletedMessageIDs = snapshot.locallyDeletedMessageIDs
        lastSuccessfulMAMSync = snapshot.lastSuccessfulMAMSync
        lastSuccessfulMAMCursor = snapshot.lastSuccessfulMAMCursor
        mamCheckpoints = snapshot.mamCheckpoints
        if mamCheckpoints.isEmpty, let lastSuccessfulMAMSync {
            mamCheckpoints[.account(jid)] = MAMArchiveCheckpoint(
                timestamp: lastSuccessfulMAMSync,
                cursor: lastSuccessfulMAMCursor
            )
        }
        messages = snapshot.messages.filter {
            !locallyDeletedMessageIDs.contains(
                Self.localDeletionKey(
                    messageID: $0.clientID,
                    conversationID: $0.conversationID
                ))
        }
        rebuildMessageIndex()
        let avatarJIDs = Set(snapshot.conversations.filter { !$0.isGroup }.map(\.jid) + [jid])
        for avatarJID in avatarJIDs {
            if let data = await avatarCache.data(for: avatarJID) {
                avatarDataByJID[avatarJID.lowercased()] = data
            }
        }
        sortConversations()
        syncWatch()
    }

    private func schedulePersist() {
        guard let store else { return }
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            try? store.save(
                locallyDeletedMessageIDs: self.locallyDeletedMessageIDs,
                rosterContactJIDs: self.rosterContactJIDs,
                lastSuccessfulMAMSync: self.lastSuccessfulMAMSync,
                lastSuccessfulMAMCursor: self.lastSuccessfulMAMCursor,
                mamCheckpoints: self.mamCheckpoints
            )
        }
    }

    private func syncWatch(immediate: Bool = false) {
        watchSyncTask?.cancel()
        watchSyncTask = nil
        if immediate {
            watchBridge.update(conversations: conversations, messages: messages)
            return
        }
        watchSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            self.watchSyncTask = nil
            self.watchBridge.update(
                conversations: self.conversations,
                messages: self.messages
            )
        }
    }

    private func loadCachedAvatarIfNeeded(for jid: String) {
        let normalized = jid.lowercased()
        guard avatarDataByJID[normalized] == nil,
            avatarCacheRequests.insert(normalized).inserted
        else { return }
        Task { [weak self] in
            guard let self, let data = await self.avatarCache.data(for: normalized) else { return }
            self.avatarDataByJID[normalized] = data
        }
    }

    private func resetMediaPreviews() {
        for directoryName in [
            "LumaMediaPreviews",
            "LumaPreview",
            "LumaForwarding",
            "LumaAttachmentDrafts",
            "LumaPhotoPicker",
            "LumaDuration",
        ] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(directoryName, isDirectory: true)
            try? FileManager.default.removeItem(at: directory)
        }
        mediaPreviewURLs = [:]
        mediaThumbnailData = [:]
        audioWaveformSamples = [:]
        loadingMediaIDs = []
        mediaViewerItem = nil
        audioPlayback.stop()
    }

    private func removeCachedMedia(for messageID: String) {
        if let url = mediaPreviewURLs.removeValue(forKey: messageID) {
            try? FileManager.default.removeItem(at: url)
            if previewURL == url { previewURL = nil }
        }
        let prefix = Self.safeFilename(messageID) + "-"
        for directoryName in ["LumaMediaPreviews", "LumaPreview", "LumaForwarding"] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(directoryName, isDirectory: true)
            let urls =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )) ?? []
            for url in urls where url.lastPathComponent.hasPrefix(prefix) {
                if previewURL == url { previewURL = nil }
                try? FileManager.default.removeItem(at: url)
            }
        }
        mediaThumbnailData.removeValue(forKey: messageID)
        audioWaveformSamples.removeValue(forKey: messageID)
        loadingMediaIDs.remove(messageID)
        if mediaViewerItem?.id == messageID {
            mediaViewerItem = nil
        }
        audioPlayback.stop()
    }

    private func cacheMediaPreview(
        data: Data,
        messageID: String,
        filename: String,
        kind: ChatMessage.Kind,
        mimeType: String,
        preparedThumbnailData: Data?
    ) async {
        do {
            let output = try Self.previewFileURL(
                messageID: messageID,
                filename: filename,
                directoryName: "LumaMediaPreviews"
            )
            try await mediaFileIO.write(data, to: output)
            mediaPreviewURLs[messageID] = output
            if let preparedThumbnailData {
                mediaThumbnailData[messageID] = preparedThumbnailData
            }
            let hasCompletePreparedPreview =
                preparedThumbnailData != nil
                && (kind == .photo || kind == .video)
            guard !hasCompletePreparedPreview else { return }
            Task { @MainActor [weak self] in
                await self?.analyzeMediaPreview(
                    at: output,
                    messageID: messageID,
                    kind: kind,
                    mimeType: mimeType
                )
            }
        } catch {
            // Sending remains possible even if local preview caching fails.
        }
    }

    private func analyzeMediaPreview(
        at url: URL,
        messageID: String,
        kind: ChatMessage.Kind,
        mimeType: String?
    ) async {
        let analysis = await mediaPreviewProcessor.analyze(
            url: url,
            kind: kind,
            mimeType: mimeType
        )
        if let thumbnailData = analysis.thumbnailData {
            mediaThumbnailData[messageID] = thumbnailData
        }
        if let waveform = analysis.waveform {
            audioWaveformSamples[messageID] = waveform
        }
        if let duration = analysis.duration,
            let index = firstMessageIndexByID[messageID],
            messages.indices.contains(index),
            messages[index].clientID == messageID,
            messages[index].duration == nil
        {
            messages[index].duration = duration
            schedulePersist()
        }
    }

    private func localAttachmentURL(
        for message: ChatMessage,
        directoryName: String
    ) async throws -> URL {
        guard let remoteURL = message.remoteAttachmentURL else {
            throw AttachmentError.missingRemoteURL
        }
        let output = try Self.previewFileURL(
            messageID: message.clientID,
            filename: message.localFilename ?? "attachment",
            directoryName: directoryName
        )
        if FileManager.default.fileExists(atPath: output.path) {
            return output
        }
        let data = try await xmpp.downloadAttachment(remoteURL)
        try await mediaFileIO.write(data, to: output)
        return output
    }

    private static func previewFileURL(
        messageID: String,
        filename: String,
        directoryName: String
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(
            "\(safeFilename(messageID))-\(safeFilename(filename))"
        )
    }

    private static func supportsInlinePreview(_ kind: ChatMessage.Kind) -> Bool {
        [.photo, .video, .audio, .voice, .videoNote].contains(kind)
    }

    private static func isValidJID(_ jid: String) -> Bool {
        let pieces = jid.split(separator: "@", omittingEmptySubsequences: false)
        return pieces.count == 2 && !pieces[0].isEmpty && !pieces[1].isEmpty
            && !jid.contains(where: { $0.isWhitespace })
    }

    private static func mediaKind(for contentType: UTType?, filename: String) -> ChatMessage.Kind {
        if contentType?.conforms(to: .image) == true { return .photo }
        if contentType?.conforms(to: .movie) == true { return .video }
        if contentType?.conforms(to: .audio) == true { return .audio }

        let fallback = UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
        if fallback?.conforms(to: .image) == true { return .photo }
        if fallback?.conforms(to: .movie) == true { return .video }
        if fallback?.conforms(to: .audio) == true { return .audio }
        return .attachment
    }

    private static func mediaTitle(kind: ChatMessage.Kind, filename: String) -> String {
        switch kind {
        case .photo: return "Фото"
        case .video: return "Видео"
        case .audio: return filename
        case .voice: return "Голосовое сообщение"
        case .videoNote: return "Видеосообщение"
        case .attachment, .location, .text, .system: return filename
        }
    }

    private static func mediaDuration(of url: URL, kind: ChatMessage.Kind) async -> TimeInterval? {
        guard [.video, .audio, .voice, .videoNote].contains(kind) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration) else { return nil }
        let seconds = time.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    private static func mediaDuration(
        data: Data,
        filename: String,
        kind: ChatMessage.Kind
    ) async -> TimeInterval? {
        guard [.video, .audio, .voice, .videoNote].contains(kind) else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaDuration", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(safeFilename(filename))")
        do {
            try data.write(to: url, options: [.atomic])
            defer { try? FileManager.default.removeItem(at: url) }
            return await mediaDuration(of: url, kind: kind)
        } catch {
            return nil
        }
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let components = value.components(separatedBy: invalid)
        let cleaned = components.filter { !$0.isEmpty }.joined(separator: "_")
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    private static func localDeletionKey(messageID: String, conversationID: String) -> String {
        conversationID.lowercased() + "\u{1F}" + messageID
    }
}

private enum SignInError: LocalizedError {
    case emptyPassword

    var errorDescription: String? {
        "Введите пароль XMPP-аккаунта."
    }
}

private enum AttachmentError: LocalizedError {
    case missingRemoteURL

    var errorDescription: String? {
        switch self {
        case .missingRemoteURL:
            return "Ссылка на вложение ещё не получена."
        }
    }
}

private enum ReconnectError: LocalizedError {
    case passwordMissing

    var errorDescription: String? {
        "Пароль не найден в Keychain. Выйдите из аккаунта и войдите снова."
    }
}
