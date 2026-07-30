import Foundation
import Martin

/// Martin 3.2.4 does not expose `DefaultRoomStore.init()` outside its module.
/// This mirrors its in-memory behavior so the app can register XEP-0045 MUC.
final class LumaRoomStore: RoomStore {
    typealias Room = RoomBase

    private let dispatcher = QueueDispatcher(label: "LumaRoomStore")
    private var roomsByJID: [BareJID: RoomBase] = [:]

    func rooms(for context: Context) -> [RoomBase] {
        dispatcher.sync {
            Array(roomsByJID.values)
        }
    }

    func room(for context: Context, with jid: BareJID) -> RoomBase? {
        dispatcher.sync {
            roomsByJID[jid]
        }
    }

    func createRoom(
        for context: Context,
        with jid: BareJID,
        nickname: String,
        password: String?
    ) -> ConversationCreateResult<RoomBase> {
        dispatcher.sync {
            if let room = roomsByJID[jid] {
                return .found(room)
            }
            let room = RoomBase(
                context: context,
                jid: jid,
                nickname: nickname,
                password: password,
                dispatcher: dispatcher
            )
            roomsByJID[jid] = room
            return .created(room)
        }
    }

    func close(room: RoomBase) -> Bool {
        dispatcher.sync {
            guard roomsByJID[room.jid] === room else { return false }
            roomsByJID.removeValue(forKey: room.jid)
            return true
        }
    }

    func initialize(context: Context) {}

    func deinitialize(context: Context) {}
}
