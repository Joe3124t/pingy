import Foundation

struct PublicKeyJWK: Codable, Equatable {
    let kty: String
    let crv: String
    let x: String
    let y: String
    let ext: Bool?
    let keyOps: [String]?

    enum CodingKeys: String, CodingKey {
        case kty
        case crv
        case x
        case y
        case ext
        case keyOps = "key_ops"
    }

    init(
        kty: String = "EC",
        crv: String = "P-256",
        x: String,
        y: String,
        ext: Bool? = true,
        keyOps: [String]? = nil
    ) {
        self.kty = kty
        self.crv = crv
        self.x = x
        self.y = y
        self.ext = ext
        self.keyOps = keyOps
    }
}
