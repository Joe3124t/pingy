import Foundation

struct IdentityPublicKeyJWK: Codable, Equatable {
    let kty: String
    let crv: String
    let x: String

    init(kty: String = "OKP", crv: String = "Ed25519", x: String) {
        self.kty = kty
        self.crv = crv
        self.x = x
    }
}

struct PublicKeyJWK: Codable, Equatable {
    let kty: String
    let crv: String
    let x: String
    let y: String?
    let ext: Bool?
    let keyOps: [String]?
    let identityPublicKey: IdentityPublicKeyJWK?

    enum CodingKeys: String, CodingKey {
        case kty
        case crv
        case x
        case y
        case ext
        case keyOps = "key_ops"
        case identityPublicKey
    }

    init(
        kty: String = "OKP",
        crv: String = "X25519",
        x: String,
        y: String? = nil,
        ext: Bool? = true,
        keyOps: [String]? = nil,
        identityPublicKey: IdentityPublicKeyJWK? = nil
    ) {
        self.kty = kty
        self.crv = crv
        self.x = x
        self.y = y
        self.ext = ext
        self.keyOps = keyOps
        self.identityPublicKey = identityPublicKey
    }
}
