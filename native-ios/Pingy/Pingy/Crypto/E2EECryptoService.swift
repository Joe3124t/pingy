import CryptoKit
import Foundation

enum CryptoServiceError: LocalizedError {
    case invalidPeerPublicKey
    case invalidEncryptedPayload
    case keychainFailure
    case unsupportedAlgorithm

    var errorDescription: String? {
        switch self {
        case .invalidPeerPublicKey:
            return "Peer public key is invalid"
        case .invalidEncryptedPayload:
            return "Encrypted payload is invalid"
        case .keychainFailure:
            return "Secure key storage failed"
        case .unsupportedAlgorithm:
            return "Unsupported encryption algorithm"
        }
    }
}

actor E2EECryptoService {
    private let privateKeyPrefix = "pingy.e2ee.private.v1."
    private var privateKeyCache: [String: P256.KeyAgreement.PrivateKey] = [:]
    private var sharedKeyCache: [String: SymmetricKey] = [:]

    func ensureIdentity(for userID: String) throws -> PublicKeyJWK {
        let privateKey = try ensurePrivateKey(for: userID)
        return makeJWK(from: privateKey.publicKey)
    }

    func encryptText(
        plaintext: String,
        userID: String,
        peerUserID: String,
        peerPublicKeyJWK: PublicKeyJWK
    ) throws -> EncryptedPayload {
        let key = try deriveConversationKey(
            userID: userID,
            peerUserID: peerUserID,
            peerPublicKeyJWK: peerPublicKeyJWK
        )

        let iv = Data((0 ..< 12).map { _ in UInt8.random(in: .min ... .max) })
        let nonce = try AES.GCM.Nonce(data: iv)
        let plaintextData = Data(plaintext.utf8)
        let sealed = try AES.GCM.seal(plaintextData, using: key, nonce: nonce)
        let body = sealed.ciphertext + sealed.tag

        return EncryptedPayload(
            iv: Base64.encode(iv),
            ciphertext: Base64.encode(body)
        )
    }

    func decryptText(
        payload: EncryptedPayload,
        userID: String,
        peerUserID: String,
        peerPublicKeyJWK: PublicKeyJWK
    ) throws -> String {
        guard payload.v == 1 else {
            throw CryptoServiceError.invalidEncryptedPayload
        }
        guard payload.alg == "AES-256-GCM" else {
            throw CryptoServiceError.unsupportedAlgorithm
        }
        guard
            let ivData = Base64.decode(payload.iv),
            let cipherData = Base64.decode(payload.ciphertext),
            cipherData.count > 16
        else {
            throw CryptoServiceError.invalidEncryptedPayload
        }

        let key = try deriveConversationKey(
            userID: userID,
            peerUserID: peerUserID,
            peerPublicKeyJWK: peerPublicKeyJWK
        )

        let nonce = try AES.GCM.Nonce(data: ivData)
        let ciphertext = cipherData.prefix(cipherData.count - 16)
        let tag = cipherData.suffix(16)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let plainData = try AES.GCM.open(box, using: key)

        guard let plainText = String(data: plainData, encoding: .utf8) else {
            throw CryptoServiceError.invalidEncryptedPayload
        }

        return plainText
    }

    func clearMemoryCaches() {
        privateKeyCache.removeAll()
        sharedKeyCache.removeAll()
    }

    private func ensurePrivateKey(for userID: String) throws -> P256.KeyAgreement.PrivateKey {
        if let cached = privateKeyCache[userID] {
            return cached
        }

        let keyName = privateKeyPrefix + userID
        if
            let stored = try? KeychainStore.shared.data(for: keyName),
            let stored,
            let restored = try? P256.KeyAgreement.PrivateKey(rawRepresentation: stored)
        {
            privateKeyCache[userID] = restored
            return restored
        }

        let created = P256.KeyAgreement.PrivateKey()
        do {
            try KeychainStore.shared.setData(created.rawRepresentation, for: keyName)
        } catch {
            throw CryptoServiceError.keychainFailure
        }

        privateKeyCache[userID] = created
        return created
    }

    private func deriveConversationKey(
        userID: String,
        peerUserID: String,
        peerPublicKeyJWK: PublicKeyJWK
    ) throws -> SymmetricKey {
        let cacheID = "\(userID):\(peerUserID):\(peerPublicKeyJWK.x):\(peerPublicKeyJWK.y)"
        if let cached = sharedKeyCache[cacheID] {
            return cached
        }

        let privateKey = try ensurePrivateKey(for: userID)
        let peerPublicKey = try makePublicKey(from: peerPublicKeyJWK)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)

        let raw = sharedSecret.withUnsafeBytes { Data($0) }
        let symmetricKey = SymmetricKey(data: raw.prefix(32))
        sharedKeyCache[cacheID] = symmetricKey
        return symmetricKey
    }

    private func makePublicKey(from jwk: PublicKeyJWK) throws -> P256.KeyAgreement.PublicKey {
        guard jwk.kty == "EC", jwk.crv == "P-256" else {
            throw CryptoServiceError.invalidPeerPublicKey
        }
        guard
            let x = Base64URL.decode(jwk.x),
            let y = Base64URL.decode(jwk.y),
            x.count == 32,
            y.count == 32
        else {
            throw CryptoServiceError.invalidPeerPublicKey
        }

        var representation = Data([0x04])
        representation.append(x)
        representation.append(y)

        do {
            return try P256.KeyAgreement.PublicKey(x963Representation: representation)
        } catch {
            throw CryptoServiceError.invalidPeerPublicKey
        }
    }

    private func makeJWK(from publicKey: P256.KeyAgreement.PublicKey) -> PublicKeyJWK {
        let bytes = publicKey.x963Representation
        let x = bytes.subdata(in: 1 ..< 33)
        let y = bytes.subdata(in: 33 ..< 65)

        return PublicKeyJWK(
            x: Base64URL.encode(x),
            y: Base64URL.encode(y),
            ext: true,
            keyOps: nil
        )
    }
}
