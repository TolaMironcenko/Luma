import Foundation

enum EncryptionPreference: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case inheritGlobal
    case enabled
    case disabled

    func resolved(globalEnabled: Bool) -> Bool {
        switch self {
        case .inheritGlobal:
            return globalEnabled
        case .enabled:
            return true
        case .disabled:
            return false
        }
    }

    var title: String {
        switch self {
        case .inheritGlobal:
            return "Как в настройках"
        case .enabled:
            return "Всегда включено"
        case .disabled:
            return "Выключено для чата"
        }
    }
}
