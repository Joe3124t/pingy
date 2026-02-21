import Foundation

enum MessageBodyFormatter {
    static func plainText(from value: JSONValue?) -> String? {
        guard let value else { return nil }

        switch value {
        case .string(let raw):
            return plainText(fromRawString: raw)
        case .object(let object):
            if isEncryptedPayload(object: object) {
                return nil
            }

            if let text = object["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty
            {
                return text
            }

            if let message = object["message"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty
            {
                return message
            }

            return nil
        case .number(let number):
            return String(number)
        case .bool(let boolValue):
            return boolValue ? "true" : "false"
        case .array:
            return nil
        case .null:
            return nil
        }
    }

    static func previewText(from value: JSONValue?, fallback: String = "Message") -> String {
        let resolved = plainText(from: value)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return resolved.isEmpty ? fallback : resolved
    }

    private static func plainText(fromRawString raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.contains("\"ciphertext\""), lowered.contains("\"iv\"") {
            return nil
        }

        if let decoded = parseJSONObject(from: trimmed) {
            if isEncryptedPayload(rawObject: decoded) {
                return nil
            }

            if let text = decoded["text"] as? String {
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.isEmpty ? nil : normalized
            }

            if let message = decoded["message"] as? String {
                let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.isEmpty ? nil : normalized
            }

            // Avoid showing raw JSON payloads in chat UI.
            return nil
        }

        return trimmed
    }

    private static func parseJSONObject(from raw: String) -> [String: Any]? {
        guard raw.hasPrefix("{"), raw.hasSuffix("}") else {
            return nil
        }

        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    private static func isEncryptedPayload(object: [String: JSONValue]) -> Bool {
        object["ciphertext"]?.stringValue != nil && object["iv"]?.stringValue != nil
    }

    private static func isEncryptedPayload(rawObject: [String: Any]) -> Bool {
        rawObject["ciphertext"] != nil && rawObject["iv"] != nil
    }
}
