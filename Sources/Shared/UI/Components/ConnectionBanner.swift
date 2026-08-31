import SwiftUI

struct ConnectionBanner: View {
    @ObservedObject var model: AppModel
    var text: String

    var body: some View {
        switch model.connectionStatus {
        case .connected:
            if model.isArchiveSyncing || !model.isOMEMOReady {
                banner(
//                    text: model.isArchiveSyncing ? "Синхронизация истории…" : "Публикация ключей OMEMO…",
                    text: "Обновление",
                    color: .clear,
                    progress: true
                )
            } else {
                Text(text)
                    .font(.headline)
            }
        case .connecting:
//            banner(icon: "antenna.radiowaves.left.and.right", text: "Подключение…", color: .clear, progress: true)
            banner(text: "Подключение", color: .clear, progress: true)
        case .disconnected:
            banner(text: "Ожидание сети", color: .clear, progress: true)
//            HStack(spacing: 8) {
//                Image(systemName: "wifi.exclamationmark")
//                Text(reason ?? "Нет соединения")
//                    .lineLimit(1)
//                Spacer()
//                Button { Task { await model.reconnect() } } label: {
//                    Label("Обновить", systemImage: "arrow.clockwise")
//                }
//                    .buttonStyle(.borderless)
//                    .fontWeight(.semibold)
//            }
//            .font(.caption)
//            .foregroundStyle(.white)
//            .padding(.horizontal, 12)
//            .padding(.vertical, 8)
////            .background(Color.red.opacity(0.88))
//            .background(Color.clear)
        }
    }

    private func banner(text: String, color: Color, progress: Bool) -> some View {
        HStack(spacing: 8) {
            if progress {
                ProgressView().controlSize(.mini).tint(.white)
            }
            Text(text)
//            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.white)
//        .padding(.horizontal, 12)
//        .padding(.vertical, 8)
//        .background(color.opacity(0.88))
    }
}

