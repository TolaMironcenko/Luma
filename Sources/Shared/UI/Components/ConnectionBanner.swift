import SwiftUI

struct ConnectionBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.connectionStatus {
        case .connected:
            if model.isArchiveSyncing || !model.isOMEMOReady {
                banner(
                    icon: model.isArchiveSyncing ? "arrow.triangle.2.circlepath" : "lock.rotation",
                    text: model.isArchiveSyncing ? "Синхронизация истории…" : "Публикация ключей OMEMO…",
                    color: .blue,
                    progress: true
                )
            }
        case .connecting:
            banner(icon: "antenna.radiowaves.left.and.right", text: "Подключение…", color: .orange, progress: true)
        case .disconnected(let reason):
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                Text(reason ?? "Нет соединения")
                    .lineLimit(1)
                Spacer()
                Button("Повторить") { Task { await model.reconnect() } }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.88))
        }
    }

    private func banner(icon: String, text: String, color: Color, progress: Bool) -> some View {
        HStack(spacing: 8) {
            if progress {
                ProgressView().controlSize(.mini).tint(.white)
            } else {
                Image(systemName: icon)
            }
            Text(text)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.88))
    }
}

