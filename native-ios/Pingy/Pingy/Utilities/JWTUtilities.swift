import Foundation

enum JWTUtilities {
    static func expirationDate(token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        guard let payloadData = Base64URL.decode(String(parts[1])) else { return nil }
        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        guard let exp = payload["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func isExpiringSoon(token: String, threshold: TimeInterval = 60) -> Bool {
        guard let date = expirationDate(token: token) else {
            return true
        }
        return date.timeIntervalSinceNow < threshold
    }
}
