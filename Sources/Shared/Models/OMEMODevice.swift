import Foundation

struct OMEMODevice: Identifiable, Hashable, Sendable {
    enum Trust: String, Sendable {
        case undecided
        case trusted
        case verified
        case compromised
    }

    let jid: String
    let deviceID: Int32
    let fingerprint: String
    let trust: Trust
    let isActive: Bool
    let isOwn: Bool

    var id: String { "\(jid)|\(deviceID)" }

    var formattedFingerprint: String {
        fingerprint.chunked(every: 8).joined(separator: " ")
    }
}

private extension String {
    func chunked(every size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var chunks: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }
        return chunks
    }
}

