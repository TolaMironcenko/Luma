import CommonCrypto
import Foundation
import Martin

/// Digest-parameterized SCRAM math (RFC 5802) for the channel-binding
/// PLUS variants. The existing SCRAMSHA512 helper stays SHA-512-only for
/// its reference-vector tests; this core serves SHA-1/256/512 PLUS.
enum SCRAMHash {
    case sha1
    case sha256
    case sha512

    var mechanismName: String {
        switch self {
        case .sha1: return "SCRAM-SHA-1"
        case .sha256: return "SCRAM-SHA-256"
        case .sha512: return "SCRAM-SHA-512"
        }
    }

    var digestLength: Int {
        switch self {
        case .sha1: return Int(CC_SHA1_DIGEST_LENGTH)
        case .sha256: return Int(CC_SHA256_DIGEST_LENGTH)
        case .sha512: return Int(CC_SHA512_DIGEST_LENGTH)
        }
    }

    private var hmacAlgorithm: CCHmacAlgorithm {
        switch self {
        case .sha1: return CCHmacAlgorithm(kCCHmacAlgSHA1)
        case .sha256: return CCHmacAlgorithm(kCCHmacAlgSHA256)
        case .sha512: return CCHmacAlgorithm(kCCHmacAlgSHA512)
        }
    }

    private var pbkdfAlgorithm: CCPseudoRandomAlgorithm {
        switch self {
        case .sha1: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
        case .sha256: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
        case .sha512: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
        }
    }

    func hmac(key: Data, data: Data) -> Data {
        var output = [UInt8](repeating: 0, count: digestLength)
        key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(
                    hmacAlgorithm,
                    keyBytes.baseAddress,
                    keyBytes.count,
                    dataBytes.baseAddress,
                    dataBytes.count,
                    &output
                )
            }
        }
        return Data(output)
    }

    func hash(data: Data) -> Data {
        var output = [UInt8](repeating: 0, count: digestLength)
        data.withUnsafeBytes { bytes in
            switch self {
            case .sha1:
                CC_SHA1(bytes.baseAddress, CC_LONG(bytes.count), &output)
            case .sha256:
                CC_SHA256(bytes.baseAddress, CC_LONG(bytes.count), &output)
            case .sha512:
                CC_SHA512(bytes.baseAddress, CC_LONG(bytes.count), &output)
            }
        }
        return Data(output)
    }

    /// PBKDF2 (RFC 5802 Hi function).
    func saltedPassword(password: String, salt: Data, iterations: Int) -> Data {
        let passwordBytes = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: digestLength)
        CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBytes,
            passwordBytes.count,
            [UInt8](salt),
            salt.count,
            pbkdfAlgorithm,
            UInt32(iterations),
            &output,
            output.count
        )
        return Data(output)
    }
}

/// Pure SCRAM channel-binding exchange math (RFC 5802 + RFC 9266): given
/// the fixed inputs of one exchange it produces the wire messages and the
/// expected server signature. Kept independent of Martin's SaslMechanism
/// so unit tests can check it against reference vectors.
struct SCRAMPlusExchange {
    let hash: SCRAMHash
    let username: String
    let password: String
    let channelBindingType: String
    let channelBindingData: Data
    let clientNonce: String

    var gs2Header: String { "p=\(channelBindingType),," }

    var clientFirstMessageBare: String { "n=\(username),r=\(clientNonce)" }

    var clientFirstMessage: String { gs2Header + clientFirstMessageBare }

    /// gs2-header || channel-binding-data (RFC 5802 §7).
    private var channelBindingInput: Data {
        (gs2Header.data(using: .utf8) ?? Data()) + channelBindingData
    }

    func clientFinalMessage(serverFirst: String) throws -> String {
        let parsed = try SCRAMSHA512.parseServerFirst(
            serverFirst,
            expectedNoncePrefix: clientNonce
        )
        let saltedPassword = hash.saltedPassword(
            password: password,
            salt: parsed.salt,
            iterations: parsed.iterations
        )
        let finalWithoutProof =
            "c=\(channelBindingInput.base64EncodedString()),r=\(parsed.nonce)"
        let authMessage = authMessageString(serverFirst: serverFirst, parsed: parsed)
        let clientKey = hash.hmac(key: saltedPassword, data: Data("Client Key".utf8))
        let storedKey = hash.hash(data: clientKey)
        let signature = hash.hmac(key: storedKey, data: Data(authMessage.utf8))
        let proof = Data(zip(clientKey, signature).map { $0 ^ $1 })
        return finalWithoutProof + ",p=" + proof.base64EncodedString()
    }

    func expectedServerSignature(serverFirst: String) throws -> Data {
        let parsed = try SCRAMSHA512.parseServerFirst(
            serverFirst,
            expectedNoncePrefix: clientNonce
        )
        let saltedPassword = hash.saltedPassword(
            password: password,
            salt: parsed.salt,
            iterations: parsed.iterations
        )
        let authMessage = authMessageString(serverFirst: serverFirst, parsed: parsed)
        let serverKey = hash.hmac(key: saltedPassword, data: Data("Server Key".utf8))
        return hash.hmac(key: serverKey, data: Data(authMessage.utf8))
    }

    private func authMessageString(
        serverFirst: String,
        parsed: SCRAMSHA512.ServerFirst
    ) -> String {
        let finalWithoutProof =
            "c=\(channelBindingInput.base64EncodedString()),r=\(parsed.nonce)"
        return clientFirstMessageBare + "," + serverFirst + "," + finalWithoutProof
    }

    /// The base64 value of the server's final `v=` attribute, or nil when
    /// the message is an `e=` error instead.
    static func verifierValue(in finalMessage: String) -> String? {
        guard finalMessage.hasPrefix("v=") else { return nil }
        let value = finalMessage.dropFirst(2).split(separator: ",", maxSplits: 1).first ?? Substring()
        guard !value.isEmpty else { return nil }
        return String(value)
    }
}

/// SCRAM with channel binding (RFC 5802 / RFC 9266, XEP-0474): the
/// tls-exporter or tls-server-end-point binding proves the SASL exchange
/// runs over the same TLS channel the client sees, defeating MITM relays.
/// Registered ahead of the plain SCRAM variants when binding data exists.
final class LumaScramPlusMechanism: SaslMechanism {
    let name: String
    private(set) var status: SaslMechanismStatus = .new

    private let hash: SCRAMHash
    private let channelBindingStore: LumaChannelBindingStore

    private var stage = 0
    private var exchange: SCRAMPlusExchange?
    private var serverFirst: String?

    init(hash: SCRAMHash, channelBindingStore: LumaChannelBindingStore) {
        self.hash = hash
        self.channelBindingStore = channelBindingStore
        name = hash.mechanismName + "-PLUS"
    }

    func reset(scopes: Set<ResetableScope>) {
        guard scopes.contains(.stream) else { return }
        status = .new
        stage = 0
        exchange = nil
        serverFirst = nil
    }

    func isAllowedToUse(_ context: Context) -> Bool {
        guard case .password(_, _, _) = context.connectionConfiguration.credentials else {
            return false
        }
        return channelBindingStore.canUseChannelBinding
    }

    func evaluateChallenge(_ input: String?, context: Context) throws -> String? {
        guard status != .completed else {
            guard input == nil else {
                throw ClientSaslException.genericError(msg: "Already authorized")
            }
            return nil
        }
        switch stage {
        case 0:
            guard case .password(let password, _, _) = context.connectionConfiguration.credentials,
                let bindingType = channelBindingStore.preferredChannelBindingType,
                let bindingData = channelBindingStore.channelBindingData(for: bindingType)
            else {
                throw ClientSaslException.genericError(
                    msg: "Channel binding unavailable")
            }
            exchange = SCRAMPlusExchange(
                hash: hash,
                username: context.userBareJid.localPart ?? "",
                password: password,
                channelBindingType: bindingType,
                channelBindingData: bindingData,
                clientNonce: SCRAMSHA512.makeNonce()
            )
            stage = 1
            status = .completedExpected
            return exchange?.clientFirstMessage.data(using: .utf8)?.base64EncodedString()

        case 1:
            guard let exchange,
                let input,
                let data = Data(base64Encoded: input),
                let decodedServerFirst = String(data: data, encoding: .utf8)
            else {
                throw ClientSaslException.badChallenge(msg: "Invalid challenge")
            }
            serverFirst = decodedServerFirst
            let final = try exchange.clientFinalMessage(serverFirst: decodedServerFirst)
            stage = 2
            return final.data(using: .utf8)?.base64EncodedString()

        case 2:
            guard let exchange, let serverFirst,
                let input,
                let data = Data(base64Encoded: input),
                let finalMessage = String(data: data, encoding: .utf8),
                let verifier = SCRAMPlusExchange.verifierValue(in: finalMessage),
                let value = Data(base64Encoded: verifier)
            else {
                throw ClientSaslException.badChallenge(msg: "Invalid final challenge")
            }
            let expected = try exchange.expectedServerSignature(serverFirst: serverFirst)
            guard value == expected else {
                throw ClientSaslException.invalidServerSignature
            }
            status = .completed
            return nil

        default:
            throw ClientSaslException.genericError(msg: "Invalid SCRAM stage")
        }
    }
}
