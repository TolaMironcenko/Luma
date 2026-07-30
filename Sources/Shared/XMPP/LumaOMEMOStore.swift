import Foundation
import MartinOMEMO

final class LumaOMEMOStore: SignalStorage {
    private let repository: OMEMOStateRepository
    private let sessionAdapter: LumaSessionStore
    private let preKeyAdapter: LumaPreKeyStore
    private let signedPreKeyAdapter: LumaSignedPreKeyStore
    private let identityAdapter: LumaIdentityKeyStore
    private let senderKeyAdapter: LumaSenderKeyStore
    private var signalContext: SignalContext?

    init(accountJID: String) {
        let repository = OMEMOStateRepository(accountJID: accountJID)
        let sessionAdapter = LumaSessionStore(repository: repository)
        let preKeyAdapter = LumaPreKeyStore(repository: repository)
        let signedPreKeyAdapter = LumaSignedPreKeyStore(repository: repository)
        let identityAdapter = LumaIdentityKeyStore(repository: repository)
        let senderKeyAdapter = LumaSenderKeyStore(repository: repository)

        self.repository = repository
        self.sessionAdapter = sessionAdapter
        self.preKeyAdapter = preKeyAdapter
        self.signedPreKeyAdapter = signedPreKeyAdapter
        self.identityAdapter = identityAdapter
        self.senderKeyAdapter = senderKeyAdapter

        super.init(
            sessionStore: sessionAdapter,
            preKeyStore: preKeyAdapter,
            signedPreKeyStore: signedPreKeyAdapter,
            identityKeyStore: identityAdapter,
            senderKeyStore: senderKeyAdapter
        )
    }

    override func setup(withContext context: SignalContext) {
        signalContext = context
        _ = regenerateKeys(wipe: false)
        super.setup(withContext: context)
    }

    override func regenerateKeys(wipe: Bool = false) -> Bool {
        guard let signalContext else { return false }
        if wipe {
            repository.reset()
        }

        let needsIdentity = identityAdapter.localRegistrationId() == 0 || identityAdapter.keyPair() == nil
        guard needsIdentity else { return true }

        let registrationID = signalContext.generateRegistrationId()
        guard let pair = SignalIdentityKeyPair.generateKeyPair(context: signalContext),
              let publicKey = pair.publicKey else {
            return false
        }

        repository.mutate { state in
            state.registrationID = registrationID
            state.identityKeyPair = pair.serialized()
            let address = SignalAddress(
                name: repository.accountJID,
                deviceId: Int32(bitPattern: registrationID)
            )
            state.identities[address.storageKey] = StoredOMEMOIdentity(
                name: address.name,
                deviceID: address.deviceId,
                fingerprint: Self.fingerprint(publicKey),
                key: publicKey,
                status: IdentityStatus.verifiedActive.rawValue,
                own: true
            )
        }
        return true
    }

    var ownFingerprint: String? {
        let registrationID = identityAdapter.localRegistrationId()
        guard registrationID != 0 else { return nil }
        return identityAdapter.identityFingerprint(
            forAddress: SignalAddress(
                name: repository.accountJID,
                deviceId: Int32(bitPattern: registrationID)
            )
        )
    }

    func devices(for jid: String) -> [OMEMODevice] {
        identityAdapter.identities(forName: jid.lowercased()).map { identity in
            OMEMODevice(
                jid: identity.address.name,
                deviceID: identity.address.deviceId,
                fingerprint: identity.fingerprint,
                trust: Self.mapTrust(identity.status),
                isActive: identity.status.isActive,
                isOwn: identity.own
            )
        }
        .sorted { lhs, rhs in lhs.deviceID < rhs.deviceID }
    }

    func hasSession(for address: SignalAddress) -> Bool {
        sessionAdapter.containsSessionRecord(forAddress: address)
    }

    func flushPendingPersistence() {
        repository.flush()
    }

    @discardableResult
    func setVerified(_ verified: Bool, jid: String, deviceID: Int32) -> Bool {
        identityAdapter.setStatus(
            verified ? .verifiedActive : .trustedActive,
            forIdentity: SignalAddress(name: jid.lowercased(), deviceId: deviceID)
        )
    }

    private static func mapTrust(_ status: IdentityStatus) -> OMEMODevice.Trust {
        switch status.trust {
        case .undecided: return .undecided
        case .trusted: return .trusted
        case .verified: return .verified
        case .compromised: return .compromised
        }
    }

    fileprivate static func fingerprint(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

private final class LumaSessionStore: SignalSessionStoreProtocol {
    private let repository: OMEMOStateRepository

    init(repository: OMEMOStateRepository) {
        self.repository = repository
    }

    func sessionRecord(forAddress address: SignalAddress) -> Data? {
        repository.read { $0.sessions[address.storageKey] }
    }

    func allDevices(for name: String, activeAndTrusted: Bool) -> [Int32] {
        repository.read { state in
            state.sessions.keys.compactMap { key in
                guard let address = StoredAddress(key), address.name == name.lowercased() else { return nil }
                guard activeAndTrusted else { return address.deviceID }
                guard let identity = state.identities[key] else { return address.deviceID }
                let status = IdentityStatus(rawValue: identity.status) ?? .undecidedActive
                let trusted = status.trust == .trusted || status.trust == .verified
                return status.isActive && trusted ? address.deviceID : nil
            }
        }
    }

    func storeSessionRecord(_ data: Data, forAddress address: SignalAddress) -> Bool {
        repository.mutate { $0.sessions[address.storageKey] = data }
        return true
    }

    func containsSessionRecord(forAddress address: SignalAddress) -> Bool {
        sessionRecord(forAddress: address) != nil
    }

    func deleteSessionRecord(forAddress address: SignalAddress) -> Bool {
        repository.mutate { $0.sessions.removeValue(forKey: address.storageKey) }
        return true
    }

    func deleteAllSessions(for name: String) -> Bool {
        repository.mutate { state in
            state.sessions = state.sessions.filter { key, _ in
                StoredAddress(key)?.name != name.lowercased()
            }
        }
        return true
    }
}

private final class LumaPreKeyStore: SignalPreKeyStoreProtocol {
    private let repository: OMEMOStateRepository
    private let deletionLock = NSLock()
    private var pendingDeletion: Set<UInt32> = []

    init(repository: OMEMOStateRepository) {
        self.repository = repository
    }

    func currentPreKeyId() -> UInt32 {
        repository.read { state in
            state.preKeys.keys.compactMap(UInt32.init).max() ?? 0
        }
    }

    func loadPreKey(withId id: UInt32) -> Data? {
        repository.read { $0.preKeys[String(id)] }
    }

    func storePreKey(_ data: Data, withId id: UInt32) -> Bool {
        repository.mutate { $0.preKeys[String(id)] = data }
        return true
    }

    func containsPreKey(withId id: UInt32) -> Bool {
        loadPreKey(withId: id) != nil
    }

    func deletePreKey(withId id: UInt32) -> Bool {
        deletionLock.lock()
        pendingDeletion.insert(id)
        deletionLock.unlock()
        return true
    }

    func flushDeletedPreKeys() -> Bool {
        deletionLock.lock()
        let ids = pendingDeletion
        pendingDeletion.removeAll()
        deletionLock.unlock()

        guard !ids.isEmpty else { return false }
        repository.mutate { state in
            ids.forEach { state.preKeys.removeValue(forKey: String($0)) }
        }
        return true
    }
}

private final class LumaSignedPreKeyStore: SignalSignedPreKeyStoreProtocol {
    private let repository: OMEMOStateRepository

    init(repository: OMEMOStateRepository) {
        self.repository = repository
    }

    func countSignedPreKeys() -> Int {
        repository.read { $0.signedPreKeys.count }
    }

    func loadSignedPreKey(withId id: UInt32) -> Data? {
        repository.read { $0.signedPreKeys[String(id)] }
    }

    func storeSignedPreKey(_ data: Data, withId id: UInt32) -> Bool {
        repository.mutate { $0.signedPreKeys[String(id)] = data }
        return true
    }

    func containsSignedPreKey(withId id: UInt32) -> Bool {
        loadSignedPreKey(withId: id) != nil
    }

    func deleteSignedPreKey(withId id: UInt32) -> Bool {
        repository.mutate { $0.signedPreKeys.removeValue(forKey: String(id)) }
        return true
    }
}

private final class LumaIdentityKeyStore: SignalIdentityKeyStoreProtocol {
    private let repository: OMEMOStateRepository

    init(repository: OMEMOStateRepository) {
        self.repository = repository
    }

    func keyPair() -> SignalIdentityKeyPairProtocol? {
        guard let data = repository.read({ $0.identityKeyPair }) else { return nil }
        return SignalIdentityKeyPair(fromKeyPairData: data)
    }

    func localRegistrationId() -> UInt32 {
        repository.read { $0.registrationID }
    }

    func save(identity: SignalAddress, key: SignalIdentityKeyProtocol?) -> Bool {
        save(identity: identity, publicKeyData: key?.publicKey)
    }

    func isTrusted(identity: SignalAddress, key: SignalIdentityKeyProtocol?) -> Bool {
        isTrusted(identity: identity, publicKeyData: key?.publicKey)
    }

    func save(identity: SignalAddress, publicKeyData: Data?) -> Bool {
        guard let publicKeyData else { return false }
        let fingerprint = LumaOMEMOStore.fingerprint(publicKeyData)
        repository.mutate { state in
            let existing = state.identities[identity.storageKey]
            let changed = existing.map { $0.key != publicKeyData } ?? false
            state.identities[identity.storageKey] = StoredOMEMOIdentity(
                name: identity.name.lowercased(),
                deviceID: identity.deviceId,
                fingerprint: fingerprint,
                key: publicKeyData,
                status: changed ? IdentityStatus.undecidedActive.rawValue : (existing?.status ?? IdentityStatus.trustedActive.rawValue),
                own: existing?.own ?? false
            )
        }
        return true
    }

    func isTrusted(identity: SignalAddress, publicKeyData: Data?) -> Bool {
        guard let publicKeyData else { return false }
        return repository.read { state in
            guard let existing = state.identities[identity.storageKey] else {
                return true
            }
            let status = IdentityStatus(rawValue: existing.status) ?? .undecidedActive
            return existing.key == publicKeyData
                && (status.trust == .trusted || status.trust == .verified)
        }
    }

    func setStatus(_ status: IdentityStatus, forIdentity identity: SignalAddress) -> Bool {
        var updated = false
        repository.mutate { state in
            guard var value = state.identities[identity.storageKey] else { return }
            value.status = status.rawValue
            state.identities[identity.storageKey] = value
            updated = true
        }
        return updated
    }

    func setStatus(active: Bool, forIdentity identity: SignalAddress) -> Bool {
        var updated = false
        repository.mutate { state in
            guard var value = state.identities[identity.storageKey],
                  let status = IdentityStatus(rawValue: value.status) else { return }
            value.status = (active ? status.toActive() : status.toInactive()).rawValue
            state.identities[identity.storageKey] = value
            updated = true
        }
        return updated
    }

    func identities(forName name: String) -> [Identity] {
        repository.read { state in
            state.identities.values.compactMap { value in
                guard value.name == name.lowercased(),
                      let status = IdentityStatus(rawValue: value.status) else { return nil }
                return Identity(
                    address: SignalAddress(name: value.name, deviceId: value.deviceID),
                    status: status,
                    fingerprint: value.fingerprint,
                    key: value.key,
                    own: value.own
                )
            }
        }
    }

    func identityFingerprint(forAddress address: SignalAddress) -> String? {
        repository.read { $0.identities[address.storageKey]?.fingerprint }
    }
}

private final class LumaSenderKeyStore: SignalSenderKeyStoreProtocol {
    private let repository: OMEMOStateRepository

    init(repository: OMEMOStateRepository) {
        self.repository = repository
    }

    func storeSenderKey(_ key: Data, address: SignalAddress?, groupId: String?) -> Bool {
        repository.mutate { state in
            state.senderKeys[Self.key(address: address, groupID: groupId)] = key
        }
        return true
    }

    func loadSenderKey(forAddress address: SignalAddress?, groupId: String?) -> Data? {
        repository.read { $0.senderKeys[Self.key(address: address, groupID: groupId)] }
    }

    private static func key(address: SignalAddress?, groupID: String?) -> String {
        "\(address?.storageKey ?? "-")|\(groupID ?? "-")"
    }
}

private final class OMEMOStateRepository: @unchecked Sendable {
    fileprivate let accountJID: String
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(
        label: "app.luma.omemo.persistence",
        qos: .utility
    )
    private let fileURL: URL
    private var state: StoredOMEMOState
    private var persistenceRevision: UInt64 = 0
    private var persistenceScheduled = false
    private var persistenceNotBeforeNanoseconds: UInt64 = 0
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private static let persistenceDebounceNanoseconds: UInt64 = 350_000_000

    init(accountJID: String) {
        self.accountJID = accountJID.lowercased()
        let fileManager = FileManager.default
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = root.appendingPathComponent("Luma/OMEMO", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("\(Self.stableHash(accountJID)).json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        state = .empty
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode(StoredOMEMOState.self, from: data) {
            state = decoded
        }
    }

    func read<T>(_ operation: (StoredOMEMOState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation(state)
    }

    func mutate(_ operation: (inout StoredOMEMOState) -> Void) {
        let shouldSchedule: Bool
        let scheduledDeadlineNanoseconds: UInt64
        lock.lock()
        operation(&state)
        persistenceRevision &+= 1
        persistenceNotBeforeNanoseconds = DispatchTime.now().uptimeNanoseconds
            &+ Self.persistenceDebounceNanoseconds
        scheduledDeadlineNanoseconds = persistenceNotBeforeNanoseconds
        shouldSchedule = !persistenceScheduled
        if shouldSchedule {
            persistenceScheduled = true
        }
        lock.unlock()

        if shouldSchedule {
            persistenceQueue.asyncAfter(
                deadline: DispatchTime(
                    uptimeNanoseconds: scheduledDeadlineNanoseconds
                )
            ) { [weak self] in
                self?.persistWhenQuiet()
            }
        }
    }

    func reset() {
        mutate { $0 = .empty }
    }

    func flush() {
        persistenceQueue.sync { [self] in
            persistUntilCurrent()
        }
    }

    private func persistWhenQuiet() {
        let snapshot: StoredOMEMOState
        let revision: UInt64
        let notBefore: UInt64

        lock.lock()
        guard persistenceScheduled else {
            lock.unlock()
            return
        }
        notBefore = persistenceNotBeforeNanoseconds
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= notBefore else {
            lock.unlock()
            persistenceQueue.asyncAfter(
                deadline: DispatchTime(uptimeNanoseconds: notBefore)
            ) { [weak self] in
                self?.persistWhenQuiet()
            }
            return
        }
        snapshot = state
        revision = persistenceRevision
        lock.unlock()

        persist(snapshot)

        lock.lock()
        if revision == persistenceRevision {
            persistenceScheduled = false
            lock.unlock()
            return
        }
        let retryAt = persistenceNotBeforeNanoseconds
        lock.unlock()
        persistenceQueue.asyncAfter(
            deadline: DispatchTime(uptimeNanoseconds: retryAt)
        ) { [weak self] in
            self?.persistWhenQuiet()
        }
    }

    private func persistUntilCurrent() {
        while true {
            let snapshot: StoredOMEMOState
            let revision: UInt64
            lock.lock()
            snapshot = state
            revision = persistenceRevision
            lock.unlock()

            persist(snapshot)

            lock.lock()
            if revision == persistenceRevision {
                persistenceScheduled = false
                lock.unlock()
                return
            }
            lock.unlock()
        }
    }

    private func persist(_ snapshot: StoredOMEMOState) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
#if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
#endif
    }

    private static func stableHash(_ value: String) -> String {
        let hash = value.lowercased().utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private struct StoredOMEMOState: Codable {
    var registrationID: UInt32
    var identityKeyPair: Data?
    var identities: [String: StoredOMEMOIdentity]
    var preKeys: [String: Data]
    var signedPreKeys: [String: Data]
    var sessions: [String: Data]
    var senderKeys: [String: Data]

    static let empty = StoredOMEMOState(
        registrationID: 0,
        identityKeyPair: nil,
        identities: [:],
        preKeys: [:],
        signedPreKeys: [:],
        sessions: [:],
        senderKeys: [:]
    )
}

private struct StoredOMEMOIdentity: Codable {
    var name: String
    var deviceID: Int32
    var fingerprint: String
    var key: Data
    var status: Int
    var own: Bool
}

private struct StoredAddress {
    let name: String
    let deviceID: Int32

    init?(_ storageKey: String) {
        guard let separator = storageKey.lastIndex(of: "|") else { return nil }
        let rawName = String(storageKey[..<separator])
        let rawDevice = String(storageKey[storageKey.index(after: separator)...])
        guard !rawName.isEmpty, let deviceID = Int32(rawDevice) else { return nil }
        name = rawName
        self.deviceID = deviceID
    }
}

private extension SignalAddress {
    var storageKey: String {
        "\(name.lowercased())|\(deviceId)"
    }
}
