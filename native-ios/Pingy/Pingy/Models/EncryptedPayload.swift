import Foundation

struct EncryptedPayload: Codable, Equatable {
    let v: Int
    let alg: String
    let iv: String
    let ciphertext: String

    init(v: Int = 1, alg: String = "AES-256-GCM", iv: String, ciphertext: String) {
        self.v = v
        self.alg = alg
        self.iv = iv
        self.ciphertext = ciphertext
    }
}
