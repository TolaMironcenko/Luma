import LocalAuthentication
import PhotosUI
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    /// When embedded as the «Настройки» tab there is no sheet to dismiss,
    /// so the confirmation toolbar button is hidden.
    var presentedAsTab: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var showingSignOutConfirmation = false
    @State private var forgetHistory = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var passcodeSheetMode: AppLockPasscodeSheet.Mode?

    var body: some View {
        NavigationStack {
            Form {
                if let account = model.account {
                    Section("Профиль") {
                        HStack(spacing: 14) {
                            AvatarView(
                                conversation: Conversation(
                                    jid: account.normalizedJID,
                                    displayName: account.displayName.isEmpty ? nil : account.displayName
                                ),
                                imageData: model.avatarData(for: account.normalizedJID),
                                size: 64
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                Text(account.displayName.isEmpty ? account.normalizedJID : account.displayName)
                                    .font(.headline)
                                PhotosPicker(selection: $avatarItem, matching: .images) {
                                    Label("Обновить аватар", systemImage: "photo.badge.plus")
                                }
                                .disabled(model.isUpdatingAvatar)
                            }
                            Spacer()
                            if model.isUpdatingAvatar {
                                ProgressView()
                            }
                        }
                    }

                    Section("Аккаунт") {
                        LabeledContent("JID", value: account.normalizedJID)
                        LabeledContent("Ресурс", value: account.effectiveResource)
                        if let host = account.manualHost {
                            LabeledContent("Сервер", value: "\(host):\(account.manualPort ?? (account.usesDirectTLS ? 5223 : 5222))")
                        } else {
                            LabeledContent("Обнаружение", value: "DNS SRV")
                        }
                    }
                }

                Section("Соединение") {
                    HStack {
                        Label(connectionTitle, systemImage: connectionIcon)
                            .foregroundStyle(connectionColor)
                        Spacer()
                        if model.connectionStatus != .connected {
                            Button("Подключить") { Task { await model.reconnect() } }
                        }
                    }
                    LabeledContent("История MAM", value: model.isArchiveSyncing ? "Синхронизация" : "Готово")
                    NavigationLink {
                        ServerInfoView(model: model)
                    } label: {
                        Label("Информация о сервере", systemImage: "server.rack")
                    }
                }

                Section("Шифрование") {
                    Toggle("OMEMO по умолчанию", isOn: Binding(
                        get: { model.globalEncryptionEnabled },
                        set: { model.setGlobalEncryptionEnabled($0) }
                    ))
                    Text("Для отдельного чата режим можно изменить через значок замка в его панели.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.globalEncryptionEnabled {
                        Label("Новые сообщения без отдельного правила отправляются открытым текстом.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    LabeledContent("Состояние", value: model.isOMEMOReady ? "Активно" : "Подготовка")
                    if let fingerprint = model.ownFingerprint {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Отпечаток этого устройства")
                                .font(.subheadline)
                            Text(fingerprint.chunked(every: 8).joined(separator: " "))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Уведомления") {
                    Label("Локальные уведомления включаются после входа", systemImage: "bell.badge")
                    Text("Для доставки при выгруженном iOS-приложении требуется APNs и XEP-0357 push-шлюз приложения. Обычный XMPP-сокет не может постоянно работать в фоне.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Блокировка приложения") {
                    Toggle("Заблокировать приложение", isOn: Binding(
                        get: { model.appLockIsEnabled },
                        set: { enabled in
                            if enabled {
                                passcodeSheetMode = .setup
                            } else {
                                passcodeSheetMode = .verify(.disableLock)
                            }
                        }
                    ))
                    if model.appLockIsEnabled {
                        Toggle("Вход по \(model.biometricUnlockName)", isOn: Binding(
                            get: { model.appLockBiometricIsEnabled },
                            set: { enabled in
                                passcodeSheetMode = .verify(
                                    enabled ? .enableBiometrics : .disableBiometrics
                                )
                            }
                        ))
                        .disabled(!model.biometricUnlockAvailable)
                        Button("Сменить пароль") {
                            passcodeSheetMode = .change
                        }
                    }
                    Text("При включённой блокировке Luma запрашивает пароль при запуске и после сворачивания. Пароль хранится в Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Приватность чата") {
                    Toggle("Показывать статус набора", isOn: Binding(
                        get: { model.typingIndicatorsEnabled },
                        set: { model.setTypingIndicatorsEnabled($0) }
                    ))
                    Text("Когда включено, Luma показывает «печатает…» и отправляет собеседникам стандартные XMPP-состояния набора.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Удалить локальную историю при выходе", isOn: $forgetHistory)

                    Button(role: .destructive) {
                        showingSignOutConfirmation = true
                    } label: {
                        Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                if !presentedAsTab {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
            }
            .confirmationDialog(
                "Выйти из Luma?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Выйти", role: .destructive) {
                    Task {
                        await model.signOut(forgetHistory: forgetHistory)
                        dismiss()
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(forgetHistory
                    ? "Пароль и локальная история будут удалены. Серверная история MAM не изменится."
                    : "Пароль будет удалён из Keychain. Серверная история MAM не изменится.")
            }
            .onChange(of: avatarItem) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { return }
                        await model.updateOwnAvatar(from: data)
                        avatarItem = nil
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
            .sheet(item: $passcodeSheetMode) { mode in
                AppLockPasscodeSheet(model: model, mode: mode)
            }
        }
#if os(macOS)
        .frame(minWidth: 500, minHeight: 560)
#endif
    }

    private var connectionTitle: String {
        switch model.connectionStatus {
        case .connected: return "Подключено"
        case .connecting: return "Подключение"
        case .disconnected: return "Отключено"
        }
    }

    private var connectionIcon: String {
        switch model.connectionStatus {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "xmark.circle.fill"
        }
    }

    private var connectionColor: Color {
        switch model.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }
}

private extension String {
    func chunked(every size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var result: [String] = []
        var cursor = startIndex
        while cursor < endIndex {
            let end = index(cursor, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[cursor..<end]))
            cursor = end
        }
        return result
    }
}
