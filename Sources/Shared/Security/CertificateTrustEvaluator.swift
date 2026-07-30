import Foundation
import Security

enum CertificateTrustEvaluator {
    /// Evaluates the peer as a TLS server for the XMPP service domain.
    ///
    /// Martin 3.2.4's legacy SocketConnector creates an SSL client-certificate
    /// policy in its default path. Luma supplies the correct server policy
    /// without weakening hostname or certificate-chain validation.
    static func evaluateServerTrust(_ trust: SecTrust, expectedDomain: String) -> Bool {
        let policy = SecPolicyCreateSSL(true, expectedDomain as CFString)
        guard SecTrustSetPolicies(trust, policy) == errSecSuccess else {
            return false
        }

        var evaluationError: CFError?
        let trusted = SecTrustEvaluateWithError(trust, &evaluationError)
        if !trusted, let evaluationError {
            let description = CFErrorCopyDescription(evaluationError) as String
            print("Luma TLS trust failed for \(expectedDomain): \(description)")
        }
        return trusted
    }
}
