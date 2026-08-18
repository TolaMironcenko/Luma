import Foundation
import SwiftUI

struct MainChatView: View {
    private enum SidebarMode: String, CaseIterable {
        case chats
        case contacts

        var title: String {
            switch self {
            case .chats: return "Чаты"
            case .contacts: return "Контакты"
            }
        }
    }

    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var sidebarMode: SidebarMode = .chats
    @State private var showingNewChat = false
    @State private var showingNewGroup = false
    @State private var showingSettings = false

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return model.conversations }
        return model.conversations.filter(matchesSearch)
    }

    private var filteredRosterContacts: [Conversation] {
        model.conversations
            .filter { !$0.isGroup && model.rosterContactJIDs.contains($0.jid) }
            .filter { searchText.isEmpty || matchesSearch($0) }
            .sorted(by: contactSort)
    }

    private var filteredGroupContacts: [Conversation] {
        model.conversations
            .filter { $0.isGroup }
            .filter { searchText.isEmpty || matchesSearch($0) }
            .sorted(by: contactSort)
    }

    private var hasStoredContacts: Bool {
        !model.rosterContactJIDs.isEmpty || model.conversations.contains { $0.isGroup }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ConnectionBanner(model: model)

                Picker("Раздел", selection: $sidebarMode) {
                    Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill")
                        .tag(SidebarMode.chats)
                    Label("Контакты", systemImage: "person.2.fill")
                        .tag(SidebarMode.contacts)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                switch sidebarMode {
                case .chats:
                    chatList
                case .contacts:
                    contactsList
                }
            }
            .navigationTitle(sidebarMode.title)
            .searchable(
                text: $searchText,
                prompt: sidebarMode == .chats ? "Поиск чатов" : "Поиск контактов"
            )
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    Button { showingNewGroup = true } label: {
                        Image(systemName: "person.3.fill")
                    }
                    .accessibilityLabel("Новый групповой чат")
                    .help("Новый групповой чат")
                    Button { showingNewChat = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Новый личный чат")
                    .help("Новый личный чат")
                }
            }
        } detail: {
            if let conversation = model.selectedConversation {
                ChatView(model: model, conversation: conversation)
                    .id(conversation.jid)
            } else {
                WelcomeDetailView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.selectedConversationID) { _, id in
            guard let id else { return }
            model.selectConversation(id: id)
        }
        .sheet(isPresented: $showingNewChat) {
            NewChatView(model: model)
        }
        .sheet(isPresented: $showingNewGroup) {
            NewGroupView(model: model)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
        }
    }

    private var chatList: some View {
        List(selection: $model.selectedConversationID) {
            ForEach(filteredConversations) { conversation in
                ConversationRow(
                    conversation: conversation,
                    imageData: model.avatarData(for: conversation.jid),
                    isEncrypted: model.encryptionEnabled(for: conversation.jid)
                )
                .tag(conversation.jid)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
        .listStyle(.plain)
        .overlay {
            if filteredConversations.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Нет чатов" : "Ничего не найдено",
                    systemImage: searchText.isEmpty ? "bubble.left" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "Создайте личный или групповой чат."
                            : "Попробуйте другой JID или имя."
                    )
                )
            }
        }
    }

    private var contactsList: some View {
        List(selection: $model.selectedConversationID) {
            if !filteredRosterContacts.isEmpty {
                Section {
                    ForEach(filteredRosterContacts) { conversation in
                        ContactRow(
                            conversation: conversation,
                            imageData: model.avatarData(for: conversation.jid)
                        )
                        .tag(conversation.jid)
                        .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                    }
                } header: {
                    Label("Люди из roster", systemImage: "person.2.fill")
                }
            }

            if !filteredGroupContacts.isEmpty {
                Section {
                    ForEach(filteredGroupContacts) { conversation in
                        ContactRow(
                            conversation: conversation,
                            imageData: model.avatarData(for: conversation.jid)
                        )
                        .tag(conversation.jid)
                        .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                    }
                } header: {
                    Label("Групповые чаты", systemImage: "person.3.fill")
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if filteredRosterContacts.isEmpty && filteredGroupContacts.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Нет контактов" : "Ничего не найдено",
                    systemImage: searchText.isEmpty ? "person.2" : "magnifyingglass",
                    description: Text(contactListDescription)
                )
            }
        }
    }

    private var contactListDescription: String {
        if !searchText.isEmpty {
            return "Попробуйте другой JID или имя."
        }
        if !hasStoredContacts, model.connectionStatus != .connected {
            return "Подключитесь к серверу, чтобы загрузить roster Prosody и групповые комнаты."
        }
        return "Добавьте человека в roster или создайте групповой чат."
    }

    private func matchesSearch(_ conversation: Conversation) -> Bool {
        conversation.displayName.localizedCaseInsensitiveContains(searchText)
            || conversation.jid.localizedCaseInsensitiveContains(searchText)
    }

    private func contactSort(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

private struct ContactRow: View {
    let conversation: Conversation
    let imageData: Data?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(conversation: conversation, imageData: imageData, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if !conversation.isGroup, conversation.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("В сети")
                    }
                }

                if conversation.isGroup {
                    HStack(spacing: 4) {
                        Image(systemName: "person.3.fill")
                        Text(groupSubtitle)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(conversation.jid)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var groupSubtitle: String {
        guard conversation.occupantCount > 0 else { return conversation.jid }
        return "\(conversation.occupantCount) участн. • \(conversation.jid)"
    }
}

private struct WelcomeDetailView: View {
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.04).ignoresSafeArea()
            ContentUnavailableView {
                Label("Luma", systemImage: "bubble.left.and.bubble.right.fill")
            } description: {
                Text("Выберите чат или начните новый защищённый диалог.")
            }
        }
    }
}
