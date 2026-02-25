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

    static func previewText(from value: JSONValue?, fallback: String = String(localized: "Message")) -> String {
        let resolved = plainText(from: value)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return resolved.isEmpty ? fallback : resolved
    }

    static func fallbackLabel(for type: MessageType?, mediaName: String? = nil) -> String {
        let cleanedName = normalizedFileName(mediaName)

        switch type {
        case .image:
            return String(localized: "Photo")
        case .video:
            return String(localized: "Video")
        case .voice:
            return String(localized: "Voice message")
        case .file:
            return cleanedName ?? String(localized: "File")
        case .text:
            return String(localized: "Message")
        case .none:
            return cleanedName ?? String(localized: "Message")
        }
    }

    static func fallbackLabel(forTypeRaw rawType: String?, mediaName: String? = nil) -> String {
        guard let rawType else {
            return fallbackLabel(for: nil, mediaName: mediaName)
        }
        return fallbackLabel(
            for: MessageType(rawValue: rawType.lowercased()),
            mediaName: mediaName
        )
    }

    static func extractedLinks(from value: JSONValue?) -> [URL] {
        let text = previewText(from: value, fallback: "")
        return extractedLinks(fromText: text)
    }

    static func extractedLinks(fromText text: String) -> [URL] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var urls: [URL] = []

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(trimmed.startIndex ..< trimmed.endIndex, in: trimmed)
            detector.matches(in: trimmed, options: [], range: range).forEach { match in
                if let url = match.url {
                    urls.append(url)
                }
            }
        }

        // Fallback for plain domains like "example.com" without scheme.
        let domainPattern = #"\b((?:www\.)?[A-Za-z0-9.-]+\.[A-Za-z]{2,})(/[^\s]*)?"#
        if let regex = try? NSRegularExpression(pattern: domainPattern, options: []) {
            let range = NSRange(trimmed.startIndex ..< trimmed.endIndex, in: trimmed)
            regex.matches(in: trimmed, options: [], range: range).forEach { match in
                guard let swiftRange = Range(match.range, in: trimmed) else { return }
                let candidate = String(trimmed[swiftRange])
                guard !candidate.lowercased().hasPrefix("http://"),
                      !candidate.lowercased().hasPrefix("https://")
                else {
                    return
                }

                if let url = URL(string: "https://\(candidate)") {
                    urls.append(url)
                }
            }
        }

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString.lowercased()
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
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

    private static func normalizedFileName(_ mediaName: String?) -> String? {
        guard let mediaName else { return nil }
        let trimmed = mediaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !looksAutoGeneratedMediaName(trimmed) else { return nil }
        return trimmed
    }

    private static func looksAutoGeneratedMediaName(_ value: String) -> Bool {
        let lowered = value.lowercased()
        guard lowered.hasPrefix("media-") else { return false }

        if lowered.contains(".jpg")
            || lowered.contains(".jpeg")
            || lowered.contains(".png")
            || lowered.contains(".webp")
            || lowered.contains(".heic")
            || lowered.contains(".mp4")
            || lowered.contains(".mov")
        {
            return true
        }

        return lowered.count >= 18
    }
}
