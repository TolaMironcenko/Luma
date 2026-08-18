import SwiftUI

/// "Server information" screen shown from Settings, mirroring Monal's
/// `ServerDetails`: a grouped list of headline + caption entries whose row
/// background is tinted green/orange/red according to the detected status.
struct ServerInfoView: View {
    @ObservedObject var model: AppModel
    @State private var isLoading = false

    var body: some View {
        List {
            if let info = model.serverInformation {
                Section {
                    statisticsEntries(info)
                } header: {
                    Text("Это статистика вашего соединения.")
                }

                Section {
                    softwareEntry(info)
                } header: {
                    Text("Это программное обеспечение, работающее на вашем сервере.")
                }

                Section {
                    connectionRows()
                } header: {
                    Text("Параметры подключения к вашему серверу.")
                }

                Section {
                    ForEach(info.capabilities) { capability in
                        entry(
                            title: capability.title,
                            detail: capability.detail,
                            status: capability.status
                        )
                    }
                } header: {
                    Text("Современные возможности XMPP, обнаруженные на вашем сервере после входа.")
                }

                Section {
                    mucEntries(info)
                } header: {
                    Text("MUC-серверы, обнаруженные на вашем сервере.")
                }

                Section {
                    stunTurnEntries(info)
                } header: {
                    Text("STUN и TURN сервисы, объявленные вашим сервером.")
                }

                Section {
                    saslEntries(info)
                } header: {
                    Text("Методы аутентификации SASL, которые поддерживает ваш сервер.")
                }
            } else if isLoading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Загрузка информации о сервере…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Нет данных о сервере",
                        systemImage: "server.rack",
                        description: Text(
                            model.connectionStatus == .connected
                                ? "Сервер не ответил на запрос. Попробуйте обновить."
                                : "Подключитесь к серверу, чтобы увидеть его возможности."
                        )
                    )
                }
            }
        }
        .navigationTitle(model.account?.domain ?? "Сервер")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
#if os(macOS)
        .listStyle(.inset)
        .frame(minWidth: 480, minHeight: 420)
#else
        .listStyle(.grouped)
#endif
    }

    // MARK: - Sections

    private func softwareEntry(_ info: ServerInformation) -> some View {
        let name = info.software.name ?? "Неизвестный сервер"
        let version = info.software.version ?? "неизвестная версия"
        let platform = info.software.os.map { ", работает на \($0)" } ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text("версия \(version)\(platform)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(
                "Рекомендации для администраторов серверов",
                destination: URL(
                    string: "https://github.com/monal-im/Monal/wiki/Considerations-for-XMPP-server-admins"
                )!
            )
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
    }

    private func connectionRows() -> some View {
        Group {
            if let account = model.account {
                if let host = account.manualHost {
                    let port = account.manualPort ?? (account.usesDirectTLS ? 5223 : 5222)
                    LabeledContent("Хост", value: "\(host):\(port)")
                    LabeledContent(
                        "Шифрование",
                        value: account.usesDirectTLS ? "Direct TLS" : "STARTTLS"
                    )
                } else {
                    LabeledContent("Хост", value: "DNS SRV")
                }
                LabeledContent("Ресурс", value: account.effectiveResource)
            }
        }
    }

    @ViewBuilder
    private func mucEntries(_ info: ServerInformation) -> some View {
        if info.conferenceServers.isEmpty {
            entry(
                title: "Нет",
                detail: "Этот сервер не предоставляет MUC-серверы.",
                status: .error
            )
        } else {
            ForEach(info.conferenceServers) { server in
                entry(
                    title: "Сервер: \(server.jid)",
                    detail: "\(server.name ?? "<неизвестное имя>") (тип «\(server.type)», категория «\(server.category)»)",
                    status: server.type == "text" ? .success : .normal
                )
            }
        }
    }

    @ViewBuilder
    private func stunTurnEntries(_ info: ServerInformation) -> some View {
        if info.externalServices.isEmpty {
            entry(
                title: "Нет",
                detail: "Этот сервер не предоставляет STUN / TURN сервисы.",
                status: .error
            )
        } else {
            ForEach(info.externalServices) { service in
                let endpoint = "\(service.host):\(service.port.map(String.init) ?? "-")"
                entry(
                    title: service.type.uppercased(),
                    detail: endpoint,
                    status: ["stun", "turn", "stuns", "turns"].contains(service.type.lowercased())
                        ? .success
                        : .error
                )
            }
        }
    }

    @ViewBuilder
    private func statisticsEntries(_ info: ServerInformation) -> some View {
        let stats = info.connectionStats
        entry(
            title: "Последний вход",
            detail: formatDate(stats.lastLogin),
            status: .normal
        )
        entry(
            title: "Сессия Stream Management установлена",
            detail: formatDate(stats.smacksSessionEstablished),
            status: .normal
        )
        entry(
            title: "Станз отправлено / не подтверждено / получено в этой сессии",
            detail: "\(stats.sent) / \(stats.unacknowledged) / \(stats.received)",
            status: .normal
        )
    }

    @ViewBuilder
    private func saslEntries(_ info: ServerInformation) -> some View {
        if info.saslMethods.isEmpty {
            entry(
                title: "Нет",
                detail: "Сервер не объявил методы SASL-аутентификации.",
                status: .error
            )
        } else {
            ForEach(info.saslMethods, id: \.self) { method in
                entry(
                    title: "Метод: \(method)",
                    detail: saslDescription(method),
                    status: method == "PLAIN" ? .warning : .normal
                )
            }
        }
    }

    private func saslDescription(_ method: String) -> String {
        switch method {
        case "PLAIN":
            return "Отправляет пароль открытым текстом (шифруется только TLS), не очень безопасно."
        case "EXTERNAL":
            return "Использует TLS-клиентские сертификаты для аутентификации."
        case let method where method.hasPrefix("SCRAM-") && method.hasSuffix("-PLUS"):
            return "Salted Challenge Response Authentication Mechanism с channel-binding."
        case let method where method.hasPrefix("SCRAM-"):
            return "Salted Challenge Response Authentication Mechanism на указанном хэше."
        default:
            return "Неизвестный метод аутентификации."
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "<неизвестно>" }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

    // MARK: - Entry

    private func entry(
        title: String,
        detail: String,
        status: ServerInformation.CapabilityStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(status.color)
    }

    private func load() async {
        guard model.connectionStatus == .connected else { return }
        isLoading = true
        await model.refreshServerInformation()
        isLoading = false
    }
}

private extension ServerInformation.CapabilityStatus {
    var color: Color {
        switch self {
        case .success: return Color.green.opacity(0.16)
        case .normal: return Color.clear
        case .warning: return Color.orange.opacity(0.16)
        case .error: return Color.red.opacity(0.16)
        }
    }
}
