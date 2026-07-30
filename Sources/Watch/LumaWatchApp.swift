import SwiftUI

@main
@MainActor
struct LumaWatchApp: App {
    @StateObject private var model = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            WatchChatListView(model: model)
        }
    }
}
