import Foundation
import Martin

final class StaticDNSSrvResolver: DNSSrvResolver {
    private let host: String
    private let port: Int
    private let directTLS: Bool

    init(host: String, port: Int, directTLS: Bool) {
        self.host = host
        self.port = port
        self.directTLS = directTLS
    }

    func resolve(
        domain: String,
        for jid: BareJID,
        completionHandler: @escaping (Result<XMPPSrvResult, DNSError>) -> Void
    ) {
        let record = XMPPSrvRecord(
            port: port,
            weight: 0,
            priority: 0,
            target: host,
            directTls: directTLS
        )
        completionHandler(.success(XMPPSrvResult(domain: domain, records: [record])))
    }

    func markAsInvalid(for domain: String, record: XMPPSrvRecord, for period: TimeInterval) {}

    func markAsInvalid(for domain: String, host: String, port: Int, for period: TimeInterval) {}
}

