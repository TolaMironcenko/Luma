import SwiftUI

@main
@MainActor
struct LumaApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(Color(red: 0.14, green: 0.56, blue: 0.96))
                .onChange(of: scenePhase) { _, phase in
                    model.setApplicationActive(phase == .active)
                }
        }
#if os(macOS)
        .defaultSize(width: 1_080, height: 720)
#endif
    }
}
