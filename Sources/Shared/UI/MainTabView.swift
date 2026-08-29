import Foundation
import SwiftData
import SwiftUI

/// Telegram-style main screen: a custom bottom tab bar (Контакты / Звонки /
/// Чаты / Настройки) shared by iOS and macOS, with a search field above the
/// chat and contact lists.
struct MainTabView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case contacts
        case calls
        case chats
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .contacts: return "Контакты"
            case .calls: return "Звонки"
            case .chats: return "Чаты"
            case .settings: return "Настройки"
            }
        }

        var icon: String {
            switch self {
            case .contacts: return "person.2"
            case .calls: return "phone"
            case .chats: return "bubble.left.and.bubble.right"
            case .settings: return "gearshape"
            }
        }

        var selectedIcon: String {
            switch self {
            case .contacts: return "person.2.fill"
            case .calls: return "phone.fill"
            case .chats: return "bubble.left.and.bubble.right.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @ObservedObject var model: AppModel
    @State private var selectedTab: Tab = .chats

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .contacts:
                    ContactsTab(model: model)
                case .calls:
                    CallsTab(model: model)
                case .chats:
                    ChatsTab(model: model)
                case .settings:
                    NavigationStack {
                        SettingsView(model: model, presentedAsTab: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            tabBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 21, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .help(tab.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        .background(.bar)
    }
}

// MARK: - Chats

private struct ChatsTab: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var showingNewChat = false
    @State private var showingNewGroup = false
    @State private var pendingGroupDeletion: Conversation?

    /// SwiftData-backed chat list. The query orders by last activity;
    /// `filteredConversations` applies the pinned-first ordering that matches
    /// `AppModel.sortConversations` (`Bool` is not `Comparable`, so pinning
    /// cannot be a `SortDescriptor`).
    @Query(
        sort: [
            SortDescriptor(\Conversation.lastActivity, order: .reverse),
        ]
    )
    private var conversations: [Conversation]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConnectionBanner(model: model)
#if os(macOS)
                searchField
#endif
                chatList
            }
            .navigationTitle("Чаты")
#if os(iOS)
            .searchable(text: $searchText, prompt: "Поиск чатов")
#endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
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
            .sheet(isPresented: $showingNewChat) {
                NewChatView(model: model)
            }
            .sheet(isPresented: $showingNewGroup) {
                NewGroupView(model: model)
            }
            .alert(
                "Удалить групповой чат?",
                isPresented: Binding(
                    get: { pendingGroupDeletion != nil },
                    set: { if !$0 { pendingGroupDeletion = nil } }
                )
            ) {
                Button("Удалить", role: .destructive) {
                    if let pendingGroupDeletion {
                        model.deleteGroupChat(jid: pendingGroupDeletion.jid)
                    }
                    pendingGroupDeletion = nil
                }
                Button("Отмена", role: .cancel) { pendingGroupDeletion = nil }
            } message: {
                Text("Чат и его история будут удалены с этого устройства. Luma выйдет из комнаты, если вы в ней.")
            }
        }
    }

    private var filteredConversations: [Conversation] {
        let source = searchText.isEmpty ? conversations : conversations.filter(matchesSearch)
        return source.sorted(by: conversationSort)
    }

    private var chatList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                NavigationLink {
                    ChatView(model: model, conversation: conversation)
                        .id(conversation.jid)
                        .onAppear { model.selectConversation(id: conversation.jid) }
                } label: {
                    ConversationRow(
                        conversation: conversation,
                        imageData: model.avatarData(for: conversation.jid),
                        isEncrypted: model.encryptionEnabled(for: conversation.jid)
                    )
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if conversation.isGroup {
                        Button(role: .destructive) {
                            pendingGroupDeletion = conversation
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
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

#if os(macOS)
    private var searchField: some View {
        TextField("Поиск чатов", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
#endif

    private func conversationSort(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            == .orderedAscending
    }

    private func matchesSearch(_ conversation: Conversation) -> Bool {
        conversation.displayName.localizedCaseInsensitiveContains(searchText)
            || conversation.jid.localizedCaseInsensitiveContains(searchText)
    }
}

// MARK: - Contacts

private struct ContactsTab: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    @Query(
        sort: [
            SortDescriptor(\Conversation.lastActivity, order: .reverse),
        ]
    )
    private var conversations: [Conversation]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConnectionBanner(model: model)
#if os(macOS)
                TextField("Поиск контактов", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
#endif
                contactsList
            }
            .navigationTitle("Контакты")
#if os(iOS)
            .searchable(text: $searchText, prompt: "Поиск контактов")
#endif
        }
    }

    private var contactsList: some View {
        List {
            if !filteredRosterContacts.isEmpty {
                Section {
                    ForEach(filteredRosterContacts) { conversation in
                        contactLink(conversation)
                            .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                    }
                } header: {
                    Label("Люди из roster", systemImage: "person.2.fill")
                }
            }

            if !filteredGroupContacts.isEmpty {
                Section {
                    ForEach(filteredGroupContacts) { conversation in
                        contactLink(conversation)
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
                    description: Text(contactListDescription),
                )
            }
        }
    }

    @ViewBuilder
    private func contactLink(_ conversation: Conversation) -> some View {
        NavigationLink {
            ChatView(model: model, conversation: conversation)
                .id(conversation.jid)
                .onAppear { model.selectConversation(id: conversation.jid) }
        } label: {
            ContactRow(
                conversation: conversation,
                imageData: model.avatarData(for: conversation.jid)
            )
        }
    }

    private var filteredRosterContacts: [Conversation] {
        conversations
            .filter { !$0.isGroup && model.rosterContactJIDs.contains($0.jid) }
            .filter { searchText.isEmpty || matchesSearch($0) }
            .sorted(by: contactSort)
    }

    private var filteredGroupContacts: [Conversation] {
        conversations
            .filter { $0.isGroup }
            .filter { searchText.isEmpty || matchesSearch($0) }
            .sorted(by: contactSort)
    }

    private var hasStoredContacts: Bool {
        !model.rosterContactJIDs.isEmpty || conversations.contains { $0.isGroup }
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

// MARK: - Calls

private struct CallsTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.callHistoryMessages.isEmpty {
                    ContentUnavailableView(
                        "Нет звонков",
                        systemImage: "phone",
                        description: Text("История звонков появится здесь после первого вызова.")
                    )
                } else {
                    List(model.callHistoryMessages) { message in
                        if let conversation = model.conversations.first(where: {
                            $0.jid == message.conversationID
                        }) {
                            NavigationLink {
                                ChatView(model: model, conversation: conversation)
                                    .id(conversation.jid)
                                    .onAppear { model.selectConversation(id: conversation.jid) }
                            } label: {
                                CallHistoryRow(model: model, message: message, conversation: conversation)
                            }
                            .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                        } else {
                            CallHistoryRow(model: model, message: message, conversation: nil)
                                .listRowInsets(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Звонки")
        }
    }
}

private struct CallHistoryRow: View {
    @ObservedObject var model: AppModel
    let message: ChatMessage
    let conversation: Conversation?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: message.callHistory?.isVideo == true ? "video.fill" : "phone.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(message.direction == .incoming && message.callHistory?.outcome == .missed
                    ? Color.red : Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation?.displayName ?? message.conversationID)
                    .font(.headline)
                    .lineLimit(1)
                Text(message.callTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            Text(message.timestamp, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
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

