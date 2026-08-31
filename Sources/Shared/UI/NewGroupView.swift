import Foundation
import SwiftUI

@MainActor
struct NewGroupView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var roomJID = ""
    @State private var name = ""
    @State private var nickname = ""
    @State private var invitees = ""
    @State private var isJoining = false

    var body: some View {
        NavigationStack {
            Form {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("room@conference.example.org", text: $roomJID)
                            .disableAutocorrection(true)
                        #if os(iOS)
                            .keyboardType(.emailAddress)
                        #endif
                        TextField("Название (необязательно)", text: $name)
                        TextField("Ваш псевдоним", text: $nickname)
                    }
                } label: {
                    Text("Комната")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("alice@example.org, bob@example.org", text: $invitees, axis: .vertical)
                            .lineLimit(2...5)
                        #if os(iOS)
                            .keyboardType(.emailAddress)
                        #endif
                        Text("Укажите JID через запятую или с новой строки. Если комнаты ещё нет, Prosody создаст её с настройками по умолчанию.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Пригласить")
                        .font(.headline)
                }

                Label(
                    "Новая комната настраивается как неанонимная и доступная участникам, чтобы поддерживать групповое OMEMO. Режим шифрования можно изменить в меню замка внутри чата.",
                    systemImage: "lock.shield.fill"
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Новая группа")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isJoining)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать / войти") { join() }
                        .fontWeight(.semibold)
                        .disabled(!canJoin || isJoining)
                }
            }
            .onAppear {
                if nickname.isEmpty { nickname = model.suggestedGroupNickname }
            }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 470)
#endif
    }

    private var canJoin: Bool {
        !roomJID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func join() {
        isJoining = true
        Task {
            await model.createOrJoinGroup(
                roomJID: roomJID,
                name: name.isEmpty ? nil : name,
                nickname: nickname,
                invitees: parsedInvitees
            )
            isJoining = false
            if model.errorMessage == nil { dismiss() }
        }
    }

    private var parsedInvitees: [String] {
        invitees.components(separatedBy: CharacterSet(charactersIn: ",;\n \t"))
            .filter { !$0.isEmpty }
    }
}
