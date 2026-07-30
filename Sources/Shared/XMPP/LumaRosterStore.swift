import Foundation
import Martin

final class LumaRosterStore: RosterStore {
    typealias RosterItem = RosterItemBase

    private let queue = DispatchQueue(label: "app.luma.roster-store")
    private var itemsByJID: [JID: RosterItemBase] = [:]
    private var rosterVersion: String?

    func clear(for context: Context) {
        queue.sync {
            itemsByJID.removeAll()
            rosterVersion = nil
        }
    }

    func items(for context: Context) -> [RosterItemBase] {
        queue.sync { Array(itemsByJID.values) }
    }

    func item(for context: Context, jid: JID) -> RosterItemBase? {
        queue.sync { itemsByJID[jid] }
    }

    func updateItem(
        for context: Context,
        jid: JID,
        name: String?,
        subscription: RosterItemSubscription,
        groups: [String],
        ask: Bool,
        annotations: [RosterItemAnnotation]
    ) {
        let item = RosterItemBase(
            jid: jid,
            name: name,
            subscription: subscription,
            groups: groups,
            ask: ask,
            annotations: annotations
        )
        queue.sync { itemsByJID[jid] = item }
    }

    func deleteItem(for context: Context, jid: JID) {
        _ = queue.sync { itemsByJID.removeValue(forKey: jid) }
    }

    func version(for context: Context) -> String? {
        queue.sync { rosterVersion }
    }

    func set(version: String?, for context: Context) {
        queue.sync { rosterVersion = version }
    }

    func initialize(context: Context) {}
    func deinitialize(context: Context) {}
}

