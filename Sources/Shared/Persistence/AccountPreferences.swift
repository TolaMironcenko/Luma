import Foundation

final class AccountPreferences {
    private let defaults: UserDefaults
    private let accountKey = "luma.active-account.v1"
    private let encryptionSettingsKey = "luma.encryption-settings.v1"
    private let chatStateSettingsKey = "luma.chat-state-settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AccountConfiguration? {
        guard let data = defaults.data(forKey: accountKey) else { return nil }
        return try? JSONDecoder().decode(AccountConfiguration.self, from: data)
    }

    func save(_ account: AccountConfiguration) throws {
        let data = try JSONEncoder().encode(account)
        defaults.set(data, forKey: accountKey)
    }

    func clear() {
        defaults.removeObject(forKey: accountKey)
    }

    func encryptionEnabled(for accountJID: String) -> Bool {
        let settings = defaults.dictionary(forKey: encryptionSettingsKey) as? [String: Bool]
        return settings?[accountJID.lowercased()] ?? true
    }

    func setEncryptionEnabled(_ enabled: Bool, for accountJID: String) {
        var settings = (defaults.dictionary(forKey: encryptionSettingsKey) as? [String: Bool]) ?? [:]
        settings[accountJID.lowercased()] = enabled
        defaults.set(settings, forKey: encryptionSettingsKey)
    }

    func chatStatesEnabled(for accountJID: String) -> Bool {
        let settings = defaults.dictionary(forKey: chatStateSettingsKey) as? [String: Bool]
        return settings?[accountJID.lowercased()] ?? true
    }

    func setChatStatesEnabled(_ enabled: Bool, for accountJID: String) {
        var settings = (defaults.dictionary(forKey: chatStateSettingsKey) as? [String: Bool]) ?? [:]
        settings[accountJID.lowercased()] = enabled
        defaults.set(settings, forKey: chatStateSettingsKey)
    }
}
