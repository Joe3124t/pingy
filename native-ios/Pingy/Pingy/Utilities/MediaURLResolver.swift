import Foundation

enum MediaURLResolver {
    static func resolve(_ value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://"), let fileURL = URL(string: trimmed) {
            return fileURL
        }

        if let parsed = URL(string: trimmed), parsed.scheme != nil {
            return parsed
        }

        // Keep pending local media previews resolvable while upload is queued.
        if shouldTreatAsLocalFilePath(trimmed) {
            return URL(fileURLWithPath: trimmed)
        }

        guard let origin = apiOriginURL else {
            return URL(string: trimmed)
        }

        let normalizedPath = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: normalizedPath, relativeTo: origin)?.absoluteURL
    }

    private static func shouldTreatAsLocalFilePath(_ value: String) -> Bool {
        guard value.hasPrefix("/") else { return false }

        // Server relative media routes must stay remote.
        if value.hasPrefix("/uploads/") || value.hasPrefix("/api/") {
            return false
        }

        if FileManager.default.fileExists(atPath: value) {
            return true
        }

        return value.hasPrefix("/private/") || value.hasPrefix("/var/") || value.hasPrefix("/tmp/")
    }

    private static let apiOriginURL: URL? = {
        guard let rawAPIBase = Bundle.main.object(forInfoDictionaryKey: "PINGY_API_BASE_URL") as? String,
              let apiURL = URL(string: rawAPIBase),
              var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }()
}
