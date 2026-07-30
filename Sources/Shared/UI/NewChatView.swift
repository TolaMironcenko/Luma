import SwiftUI

struct NewChatView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var jid = ""
    @State private var name = ""
    @State private var addToRoster = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Контакт") {
                    TextField("user@example.org", text: $jid)
                        .disableAutocorrection(true)
                    TextField("Имя (необязательно)", text: $name)
                }
                Section {
                    Toggle("Добавить в roster", isOn: $addToRoster)
                } footer: {
                    Text("Начать чат можно с любым полным JID. Для шифрования у контакта должно быть опубликовано хотя бы одно OMEMO-устройство.")
                }
            }
            .navigationTitle("Новый чат")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Начать") {
                        model.openConversation(
                            jid: jid,
                            name: name.isEmpty ? nil : name,
                            addToRoster: addToRoster
                        )
                        if model.errorMessage == nil { dismiss() }
                    }
                    .fontWeight(.semibold)
                    .disabled(jid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
#endif
    }
}
