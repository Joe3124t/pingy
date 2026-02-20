import Foundation

enum MediaURLResolver {
    static func resolve(_ value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let parsed = URL(string: trimmed), parsed.scheme != nil {
            return parsed
        }

        guard let origin = apiOriginURL else {
            return URL(string: trimmed)
        }

        let normalizedPath = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: normalizedPath, relativeTo: origin)?.absoluteURL
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
