import Foundation

final class APIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = session
        self.decoder = JSONDecoder()
    }

    func request<T: Decodable>(
        _ endpoint: Endpoint,
        accessToken: String? = nil
    ) async throws -> T {
        let (data, response) = try await execute(endpoint, accessToken: accessToken)

        if data.isEmpty {
            throw APIError.decodingError
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            AppLogger.error("Decode failed for \(endpoint.path): \(error.localizedDescription)")
            throw APIError.decodingError
        }
    }

    func requestNoContent(
        _ endpoint: Endpoint,
        accessToken: String? = nil
    ) async throws {
        _ = try await execute(endpoint, accessToken: accessToken)
    }

    func requestRawData(
        _ endpoint: Endpoint,
        accessToken: String? = nil
    ) async throws -> Data {
        let (data, _) = try await execute(endpoint, accessToken: accessToken)
        return data
    }

    private func execute(
        _ endpoint: Endpoint,
        accessToken: String?
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = 30

        request.setValue("application/json", forHTTPHeaderField: "Accept")

        endpoint.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                return (data, httpResponse)
            case 401:
                throw APIError.unauthorized
            default:
                let message = Self.extractServerError(from: data) ?? "Request failed (\(httpResponse.statusCode))"
                throw APIError.server(statusCode: httpResponse.statusCode, message: message)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    private static func extractServerError(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = object["message"] as? String {
                return message
            }
            if let error = object["error"] as? String {
                return error
            }
        }

        return String(data: data, encoding: .utf8)
    }
}
