import Foundation
import UserNotifications

final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        // UNUserNotificationCenter keeps a weak delegate. AppModel retains this
        // coordinator for the lifetime of the application.
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func showIncomingMessage(id: String, sender: String, body: String, conversationID: String) {
        let content = UNMutableNotificationContent()
        content.title = sender
        content.body = body
        content.sound = .default
        content.threadIdentifier = conversationID
        content.userInfo = ["conversation": conversationID]

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // System notifications are normally hidden while an app is in the
        // foreground. Explicitly request the same banner/list/sound treatment
        // used when Luma is backgrounded.
        [.banner, .list, .sound]
    }
}
