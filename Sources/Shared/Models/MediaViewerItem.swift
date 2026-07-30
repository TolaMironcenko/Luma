import Foundation

struct MediaViewerItem: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let kind: ChatMessage.Kind
    let title: String
}
