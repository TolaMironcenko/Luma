import Foundation

actor AvatarCache {
    private let directory: URL

    init() {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = base.appendingPathComponent("Luma/Avatars", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func data(for jid: String) -> Data? {
        try? Data(contentsOf: fileURL(for: jid))
    }

    func store(_ data: Data, for jid: String) throws {
        try data.write(to: fileURL(for: jid), options: [.atomic])
#if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL(for: jid).path
        )
#endif
    }

    private func fileURL(for jid: String) -> URL {
        directory.appendingPathComponent("\(Self.stableHash(jid)).avatar")
    }

    private static func stableHash(_ value: String) -> String {
        let hash = value.lowercased().utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16, uppercase: false)
    }
}
