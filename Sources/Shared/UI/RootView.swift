import QuickLook
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Group {
                if model.account == nil {
                    LoginView(model: model)
                } else {
                    MainChatView(model: model)
                }
            }

            if let item = model.mediaViewerItem {
                MediaViewer(item: item, onClose: model.closeMediaViewer)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(100)
            }

            if let call = model.activeCall {
                CallView(model: model, call: call)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                    .zIndex(200)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.account?.id)
        .animation(.easeInOut(duration: 0.2), value: model.mediaViewerItem?.id)
        .animation(.easeInOut(duration: 0.2), value: model.activeCall?.id)
        .alert("Luma", isPresented: errorBinding) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "Неизвестная ошибка")
        }
        .quickLookPreview($model.previewURL)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { visible in if !visible { model.clearError() } }
        )
    }
}
