import Foundation

actor VoicePlaybackManager {
    static let shared = VoicePlaybackManager()

    private init() {}

    func loadPlayableAudio(
        sourceURL: URL,
        conversationID: String,
        messageID: String
    ) async throws -> Data {
        if let messageScopedData = VoiceMediaDiskCache.shared.data(forMessageID: messageID) {
            return messageScopedData
        }

        let token = currentAccessToken()
        let candidateTokens: [String?] = token?.isEmpty == false ? [token, nil] : [nil]
        let urlCandidates = audioSourceCandidates(from: sourceURL)
        var lastError: Error?

        for candidateURL in urlCandidates {
            if candidateURL.isFileURL {
                if let data = try? Data(contentsOf: candidateURL), !data.isEmpty {
                    return data
                }
                continue
            }

            if let cached = VoiceMediaDiskCache.shared.data(for: candidateURL) {
                if candidateURL != sourceURL {
                    VoiceMediaDiskCache.shared.store(data: cached, for: sourceURL)
                }
                VoiceMediaDiskCache.shared.store(data: cached, forMessageID: messageID)
                return cached
            }

            for (index, candidateToken) in candidateTokens.enumerated() {
                do {
                    let data = try await fetchAudioData(
                        from: candidateURL,
                        accessToken: candidateToken,
                        allowJSONRedirect: true
                    )
                    VoiceMediaDiskCache.shared.store(data: data, for: candidateURL)
                    if candidateURL != sourceURL {
                        VoiceMediaDiskCache.shared.store(data: data, for: sourceURL)
                    }
                    VoiceMediaDiskCache.shared.store(data: data, forMessageID: messageID)
                    return data
                } catch {
                    lastError = error
                    if index < candidateTokens.count - 1 {
                        try? await Task.sleep(nanoseconds: 220_000_000)
                    }
                }
            }
        }

        if let staleMessageScoped = VoiceMediaDiskCache.shared.data(forMessageID: messageID, allowExpired: true) {
            return staleMessageScoped
        }

        if let stale = VoiceMediaDiskCache.shared.data(for: sourceURL, allowExpired: true) {
            VoiceMediaDiskCache.shared.store(data: stale, forMessageID: messageID)
            return stale
        }

        if let refreshed = try await refreshSignedMediaAndFetch(
            sourceURL: sourceURL,
            conversationID: conversationID,
            messageID: messageID,
            token: token
        ) {
            return refreshed
        }

        throw lastError ?? APIError.server(statusCode: 500, message: "Voice media unavailable")
    }

    private func refreshSignedMediaAndFetch(
        sourceURL: URL,
        conversationID: String,
        messageID: String,
        token: String?
    ) async throws -> Data? {
        guard !conversationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let tokens: [String?] = token?.isEmpty == false ? [token, nil] : [nil]
        let decoder = JSONDecoder()

        for endpointURL in signedMediaRefreshEndpoints(conversationID: conversationID) {
            for endpointToken in tokens {
                var request = URLRequest(url: endpointURL)
                request.httpMethod = "GET"
                request.timeoutInterval = 20
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                if let endpointToken, !endpointToken.isEmpty {
                    request.setValue("Bearer \(endpointToken)", forHTTPHeaderField: "Authorization")
                }

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200 ... 299).contains(http.statusCode),
                          !data.isEmpty
                    else {
                        continue
                    }

                    guard let list = try? decoder.decode(MessageListResponse.self, from: data),
                          let refreshedMessage = list.messages.first(where: { $0.id == messageID }),
                          let refreshedURL = MediaURLResolver.resolve(refreshedMessage.mediaUrl)
                    else {
                        continue
                    }

                    let retryCandidates = audioSourceCandidates(from: refreshedURL)
                    for retryURL in retryCandidates {
                        if let cached = VoiceMediaDiskCache.shared.data(for: retryURL) {
                            VoiceMediaDiskCache.shared.store(data: cached, for: sourceURL)
                            VoiceMediaDiskCache.shared.store(data: cached, forMessageID: messageID)
                            return cached
                        }

                        for retryToken in tokens {
                            if let downloaded = try? await fetchAudioData(
                                from: retryURL,
                                accessToken: retryToken,
                                allowJSONRedirect: true
                            ) {
                                VoiceMediaDiskCache.shared.store(data: downloaded, for: retryURL)
                                VoiceMediaDiskCache.shared.store(data: downloaded, for: sourceURL)
                                VoiceMediaDiskCache.shared.store(data: downloaded, forMessageID: messageID)
                                return downloaded
                            }
                        }
                    }
                } catch {
                    continue
                }
            }
        }

        return nil
    }

    private func signedMediaRefreshEndpoints(conversationID: String) -> [URL] {
        guard let encodedConversationID = conversationID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return []
        }

        var candidates: [URL] = []
        let configuredBase = (Bundle.main.object(forInfoDictionaryKey: "PINGY_API_BASE_URL") as? String)
            ?? "https://pingy-backend-production.up.railway.app/api"

        if let configuredURL = URL(string: configuredBase) {
            candidates.append(contentsOf: messageListEndpointCandidates(baseURL: configuredURL, conversationID: encodedConversationID))
        }

        if let fallbackURL = URL(string: "https://pingy-backend-production.up.railway.app/api") {
            candidates.append(contentsOf: messageListEndpointCandidates(baseURL: fallbackURL, conversationID: encodedConversationID))
        }

        var deduplicated: [URL] = []
        for candidate in candidates where !deduplicated.contains(candidate) {
            deduplicated.append(candidate)
        }
        return deduplicated
    }

    private func messageListEndpointCandidates(baseURL: URL, conversationID: String) -> [URL] {
        var endpoints: [URL] = []
        let normalized = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalized.lowercased().hasSuffix("/api") {
            if let direct = URL(string: "\(normalized)/messages/\(conversationID)?limit=100") {
                endpoints.append(direct)
            }
            let trimmed = String(normalized.dropLast(4))
            if let fallback = URL(string: "\(trimmed)/messages/\(conversationID)?limit=100") {
                endpoints.append(fallback)
            }
        } else {
            if let direct = URL(string: "\(normalized)/messages/\(conversationID)?limit=100") {
                endpoints.append(direct)
            }
            if let fallback = URL(string: "\(normalized)/api/messages/\(conversationID)?limit=100") {
                endpoints.append(fallback)
            }
        }

        return endpoints
    }

    private func audioSourceCandidates(from sourceURL: URL) -> [URL] {
        var candidates: [URL] = [sourceURL]

        if sourceURL.isFileURL {
            let normalizedPath = sourceURL.path.removingPercentEncoding ?? sourceURL.path
            let normalizedFileURL = URL(fileURLWithPath: normalizedPath)
            if normalizedFileURL != sourceURL {
                candidates.append(normalizedFileURL)
            }
            return candidates
        }

        if let components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) {
            if components.path.hasPrefix("/uploads/"), components.queryItems?.isEmpty == false {
                var stripped = components
                stripped.queryItems = nil
                if let strippedURL = stripped.url {
                    candidates.append(strippedURL)
                }
            }

            if components.path.hasSuffix("/api/media/access"),
               let mediaToken = components.queryItems?.first(where: { $0.name == "m" })?.value,
               let decoded = decodeMediaTokenURL(mediaToken)
            {
                candidates.append(decoded)
            }

            if components.path.hasSuffix("/api/media/access"),
               let pathToken = components.queryItems?.first(where: { $0.name == "u" })?.value,
               let decodedPath = pathToken.removingPercentEncoding
            {
                let relativePath = decodedPath.hasPrefix("/") ? decodedPath : "/\(decodedPath)"
                if let origin = mediaOrigin(from: sourceURL),
                   let uploadURL = URL(string: relativePath, relativeTo: origin)?.absoluteURL
                {
                    candidates.append(uploadURL)
                }
            }

            if components.path.hasPrefix("/uploads/") || components.path.hasSuffix("/api/media/access") {
                for origin in configuredMediaOrigins() {
                    if let rewritten = URL(string: components.path, relativeTo: origin)?.absoluteURL {
                        candidates.append(rewritten)
                    }
                }
            }
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.absoluteString
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func mediaOrigin(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func configuredMediaOrigins() -> [URL] {
        var origins: [URL] = []
        let configuredBase = (Bundle.main.object(forInfoDictionaryKey: "PINGY_API_BASE_URL") as? String)
            ?? "https://pingy-backend-production.up.railway.app/api"

        if let configuredURL = URL(string: configuredBase),
           let origin = mediaOrigin(from: configuredURL)
        {
            origins.append(origin)
        }

        if let fallback = URL(string: "https://pingy-backend-production.up.railway.app") {
            origins.append(fallback)
        }

        var deduplicated: [URL] = []
        for origin in origins where !deduplicated.contains(origin) {
            deduplicated.append(origin)
        }
        return deduplicated
    }

    private func decodeMediaTokenURL(_ token: String) -> URL? {
        let normalized = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        let padded = remainder == 0 ? normalized : normalized + String(repeating: "=", count: 4 - remainder)

        guard let data = Data(base64Encoded: padded),
              let raw = String(data: data, encoding: .utf8),
              let decodedURL = URL(string: raw),
              decodedURL.scheme?.hasPrefix("http") == true
        else {
            return nil
        }
        return decodedURL
    }

    private func fetchAudioData(from sourceURL: URL, accessToken: String?, allowJSONRedirect: Bool) async throws -> Data {
        var request = URLRequest(url: sourceURL)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 30
        request.setValue("audio/*,application/octet-stream;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw APIError.server(statusCode: http.statusCode, message: "Voice media unavailable")
        }

        if allowJSONRedirect,
           let redirected = extractMediaURL(fromJSON: data, relativeTo: sourceURL)
        {
            let redirectedData = try await fetchAudioData(
                from: redirected,
                accessToken: nil,
                allowJSONRedirect: false
            )
            VoiceMediaDiskCache.shared.store(data: redirectedData, for: sourceURL)
            return redirectedData
        }

        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           (contentType.contains("text/html") || contentType.contains("application/xhtml+xml"))
        {
            throw APIError.server(statusCode: http.statusCode, message: "Voice media returned invalid payload")
        }

        if isLikelyHTMLPayload(data) {
            throw APIError.server(statusCode: 500, message: "Voice media returned invalid html payload")
        }

        guard !data.isEmpty else {
            throw APIError.server(statusCode: 500, message: "Voice media response is empty")
        }

        VoiceMediaDiskCache.shared.store(data: data, for: sourceURL)
        return data
    }

    private func extractMediaURL(fromJSON data: Data, relativeTo sourceURL: URL) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let keys = ["url", "mediaUrl", "signedUrl", "downloadUrl", "href"]
        for key in keys {
            guard let raw = object[key] as? String, !raw.isEmpty else { continue }
            if let absolute = URL(string: raw), absolute.scheme != nil {
                return absolute
            }
            if let relative = URL(string: raw, relativeTo: sourceURL)?.absoluteURL {
                return relative
            }
        }
        return nil
    }

    private func isLikelyHTMLPayload(_ data: Data) -> Bool {
        let prefix = data.prefix(256)
        guard let text = String(data: prefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }

        return text.hasPrefix("<!doctype html")
            || text.hasPrefix("<html")
            || text.contains("<body>")
    }

    private func currentAccessToken() -> String? {
        let defaultsToken = UserDefaults.standard.string(forKey: "pingy.session.accessToken.fallback")
        if let defaultsToken, !defaultsToken.isEmpty {
            return defaultsToken
        }

        if let keychainToken = try? KeychainStore.shared.string(for: "pingy.session.accessToken"),
           !keychainToken.isEmpty
        {
            return keychainToken
        }

        return nil
    }
}
