import CryptoKit
import Foundation
import MartinOMEMO

final class CryptoKitAESGCMEngine: AES_GCM_Engine {
    func encrypt(
        iv: Data,
        key: Data,
        message: Data,
        output: UnsafeMutablePointer<Data>?,
        tag: UnsafeMutablePointer<Data>?
    ) -> Bool {
        do {
            let nonce = try AES.GCM.Nonce(data: iv)
            let sealed = try AES.GCM.seal(
                message,
                using: SymmetricKey(data: key),
                nonce: nonce
            )
            output?.pointee = sealed.ciphertext
            tag?.pointee = sealed.tag
            return true
        } catch {
            return false
        }
    }

    func decrypt(
        iv: Data,
        key: Data,
        encoded: Data,
        auth tag: Data?,
        output: UnsafeMutablePointer<Data>?
    ) -> Bool {
        do {
            let nonce = try AES.GCM.Nonce(data: iv)
            let authenticationTag: Data
            let ciphertext: Data

            if let tag {
                authenticationTag = tag
                ciphertext = encoded
            } else {
                guard encoded.count >= 16 else { return false }
                authenticationTag = Data(encoded.suffix(16))
                ciphertext = Data(encoded.dropLast(16))
            }

            let box = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertext,
                tag: authenticationTag
            )
            output?.pointee = try AES.GCM.open(box, using: SymmetricKey(data: key))
            return true
        } catch {
            return false
        }
    }
}
