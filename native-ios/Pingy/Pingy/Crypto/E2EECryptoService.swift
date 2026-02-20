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
    private let agreementPrivateKeyPrefix = "pingy.e2ee.x25519.private.v2."
    private let identityPrivateKeyPrefix = "pingy.e2ee.ed25519.private.v2."
    private let keyDerivationSalt = Data("pingy-v2-aesgcm".utf8)

    private var agreementPrivateKeyCache: [String: Curve25519.KeyAgreement.PrivateKey] = [:]
    private var identityPrivateKeyCache: [String: Curve25519.Signing.PrivateKey] = [:]
    private var sharedKeyCache: [String: SymmetricKey] = [:]

    private var currentDeviceID: String {
        DeviceIdentityStore.shared.currentDeviceID()
    }

    func ensureIdentity(for userID: String) throws -> PublicKeyJWK {
        let agreementPrivateKey = try ensureAgreementPrivateKey(for: userID)
        let identityPrivateKey = try ensureIdentityPrivateKey(for: userID)
        return makeJWK(
            agreementPublicKey: agreementPrivateKey.publicKey,
            identityPublicKey: identityPrivateKey.publicKey
        )
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

        AppLogger.debug(
            "E2EE encrypt success for peer \(peerUserID), ivBytes=\(iv.count), cipherBytes=\(sealed.ciphertext.count), tagBytes=\(sealed.tag.count)"
        )

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
            ivData.count == 12,
            cipherData.count > 16
        else {
            AppLogger.error("E2EE decrypt payload validation failed for peer \(peerUserID)")
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

        AppLogger.debug(
            "E2EE decrypt success for peer \(peerUserID), ivBytes=\(ivData.count), cipherBytes=\(ciphertext.count), tagBytes=\(tag.count)"
        )

        return plainText
    }

    func clearMemoryCaches() {
        agreementPrivateKeyCache.removeAll()
        identityPrivateKeyCache.removeAll()
        sharedKeyCache.removeAll()
    }

    func clearIdentityFromKeychain(for userID: String) {
        let binding = keyBinding(for: userID)
        try? KeychainStore.shared.delete(agreementPrivateKeyPrefix + binding)
        try? KeychainStore.shared.delete(identityPrivateKeyPrefix + binding)
        clearMemoryCaches()
    }

    func invalidateConversationKey(userID: String, peerUserID: String) {
        let prefix = "\(keyBinding(for: userID)):\(peerUserID):"
        sharedKeyCache = sharedKeyCache.filter { !$0.key.hasPrefix(prefix) }
    }

    private func keyBinding(for userID: String) -> String {
        "\(userID).\(currentDeviceID)"
    }

    private func ensureAgreementPrivateKey(for userID: String) throws -> Curve25519.KeyAgreement.PrivateKey {
        let binding = keyBinding(for: userID)
        if let cached = agreementPrivateKeyCache[binding] {
            return cached
        }

        let keyName = agreementPrivateKeyPrefix + binding
        if
            let storedData = try? KeychainStore.shared.data(for: keyName),
            let restored = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: storedData)
        {
            agreementPrivateKeyCache[binding] = restored
            return restored
        }

        let created = Curve25519.KeyAgreement.PrivateKey()
        do {
            try KeychainStore.shared.setData(created.rawRepresentation, for: keyName)
        } catch {
            throw CryptoServiceError.keychainFailure
        }

        agreementPrivateKeyCache[binding] = created
        return created
    }

    private func ensureIdentityPrivateKey(for userID: String) throws -> Curve25519.Signing.PrivateKey {
        let binding = keyBinding(for: userID)
        if let cached = identityPrivateKeyCache[binding] {
            return cached
        }

        let keyName = identityPrivateKeyPrefix + binding
        if
            let storedData = try? KeychainStore.shared.data(for: keyName),
            let restored = try? Curve25519.Signing.PrivateKey(rawRepresentation: storedData)
        {
            identityPrivateKeyCache[binding] = restored
            return restored
        }

        let created = Curve25519.Signing.PrivateKey()
        do {
            try KeychainStore.shared.setData(created.rawRepresentation, for: keyName)
        } catch {
            throw CryptoServiceError.keychainFailure
        }

        identityPrivateKeyCache[binding] = created
        return created
    }

    private func deriveConversationKey(
        userID: String,
        peerUserID: String,
        peerPublicKeyJWK: PublicKeyJWK
    ) throws -> SymmetricKey {
        let cacheID = "\(keyBinding(for: userID)):\(peerUserID):\(peerPublicKeyJWK.kty):\(peerPublicKeyJWK.crv):\(peerPublicKeyJWK.x)"
        if let cached = sharedKeyCache[cacheID] {
            return cached
        }

        let privateKey = try ensureAgreementPrivateKey(for: userID)
        let peerPublicKey = try makePublicKey(from: peerPublicKeyJWK)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: keyDerivationSalt,
            sharedInfo: Data(cacheID.utf8),
            outputByteCount: 32
        )
        sharedKeyCache[cacheID] = symmetricKey
        return symmetricKey
    }

    private func makePublicKey(from jwk: PublicKeyJWK) throws -> Curve25519.KeyAgreement.PublicKey {
        guard jwk.kty == "OKP", jwk.crv == "X25519" else {
            throw CryptoServiceError.invalidPeerPublicKey
        }
        guard
            let x = Base64URL.decode(jwk.x),
            x.count == 32
        else {
            throw CryptoServiceError.invalidPeerPublicKey
        }

        do {
            return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: x)
        } catch {
            throw CryptoServiceError.invalidPeerPublicKey
        }
    }

    private func makeJWK(
        agreementPublicKey: Curve25519.KeyAgreement.PublicKey,
        identityPublicKey: Curve25519.Signing.PublicKey
    ) -> PublicKeyJWK {
        PublicKeyJWK(
            kty: "OKP",
            crv: "X25519",
            x: Base64URL.encode(agreementPublicKey.rawRepresentation),
            y: nil,
            ext: true,
            keyOps: nil,
            identityPublicKey: IdentityPublicKeyJWK(
                kty: "OKP",
                crv: "Ed25519",
                x: Base64URL.encode(identityPublicKey.rawRepresentation)
            )
        )
    }
}
