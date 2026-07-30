import Foundation

enum NotificationPolicy {
    static func shouldPresentMessage(
        inserted: Bool,
        isOutgoing: Bool,
        appIsActive: Bool,
        selectedConversationID: String?,
        conversationID: String
    ) -> Bool {
        guard inserted, !isOutgoing else { return false }
        guard appIsActive else { return true }
        return selectedConversationID?.lowercased() != conversationID.lowercased()
    }
}
