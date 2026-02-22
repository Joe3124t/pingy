import Foundation

enum MessageBodyFormatter {
    private static let preferredKeys = [
        "text",
        "message",
        "body",
        "content",
        "caption",
        "plainText",
        "plaintext",
        "value",
    ]
    private static let ignoredMetadataKeys = Set([
        "id",
        "type",
        "mime",
        "mediaurl",
        "medianame",
        "mediasize",
        "voicedurationms",
        "isEncrypted",
        "isencrypted",
        "v",
        "alg",
        "iv",
        "ciphertext",
        "tag",
        "nonce",
        "createdat",
        "updatedat",
    ])

    static func plainText(from value: JSONValue?) -> String? {
        guard let value else { return nil }

        return extractText(from: value, depth: 0)
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

        if let decoded = parseJSON(from: trimmed) {
            if isEncryptedPayload(rawObject: decoded as? [String: Any] ?? [:]) {
                return nil
            }

            if let extracted = extractText(fromRawJSON: decoded, depth: 0) {
                return extracted
            }
        }

        return trimmed
    }

    private static func parseJSON(from raw: String) -> Any? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        return object
    }

    private static func extractText(from value: JSONValue, depth: Int) -> String? {
        guard depth <= 8 else { return nil }

        switch value {
        case .string(let raw):
            return plainText(fromRawString: raw)

        case .object(let object):
            if isEncryptedPayload(object: object) {
                return nil
            }

            for key in preferredKeys {
                if let nested = object[key], let extracted = extractText(from: nested, depth: depth + 1) {
                    return extracted
                }
            }

            for (key, nested) in object {
                if ignoredMetadataKeys.contains(key.lowercased()) {
                    continue
                }
                if let extracted = extractText(from: nested, depth: depth + 1) {
                    return extracted
                }
            }

            return nil

        case .array(let array):
            for nested in array {
                if let extracted = extractText(from: nested, depth: depth + 1) {
                    return extracted
                }
            }
            return nil

        case .number(let number):
            return depth == 0 ? String(number) : nil

        case .bool(let boolValue):
            return depth == 0 ? (boolValue ? "true" : "false") : nil

        case .null:
            return nil
        }
    }

    private static func extractText(fromRawJSON value: Any, depth: Int) -> String? {
        guard depth <= 8 else { return nil }

        if let stringValue = value as? String {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }

        if let dictionary = value as? [String: Any] {
            if isEncryptedPayload(rawObject: dictionary) {
                return nil
            }

            for key in preferredKeys {
                if let nested = dictionary[key],
                   let extracted = extractText(fromRawJSON: nested, depth: depth + 1)
                {
                    return extracted
                }
            }

            for (key, nested) in dictionary {
                if ignoredMetadataKeys.contains(key.lowercased()) {
                    continue
                }
                if let extracted = extractText(fromRawJSON: nested, depth: depth + 1) {
                    return extracted
                }
            }

            return nil
        }

        if let array = value as? [Any] {
            for nested in array {
                if let extracted = extractText(fromRawJSON: nested, depth: depth + 1) {
                    return extracted
                }
            }
            return nil
        }

        return nil
    }

    private static func isEncryptedPayload(object: [String: JSONValue]) -> Bool {
        object["ciphertext"]?.stringValue != nil && object["iv"]?.stringValue != nil
    }

    private static func isEncryptedPayload(rawObject: [String: Any]) -> Bool {
        rawObject["ciphertext"] != nil && rawObject["iv"] != nil
    }
}
