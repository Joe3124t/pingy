import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case server(statusCode: Int, message: String)
    case decodingError
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid server URL")
        case .invalidResponse:
            return String(localized: "Invalid server response")
        case .unauthorized:
            return String(localized: "Session expired. Please log in again.")
        case .server(_, let message):
            let lowered = message.lowercased()
            if lowered.contains("backend write error") || lowered.contains("error 54113") {
                return String(localized: "Media upload is temporarily unavailable. Please try again in a moment.")
            }
            if lowered.contains("internal server error") {
                return String(localized: "Server is temporarily busy. Please try again in a moment.")
            }
            if lowered.contains("unsupported") && lowered.contains("mime") {
                return String(localized: "This file format is not supported.")
            }
            if lowered.contains("route not found") {
                return String(localized: "Route not found")
            }
            return message
        case .decodingError:
            return String(localized: "We couldn't sync data from server. Pull to refresh and try again.")
        case .network(let error):
            if (error as NSError).domain == NSURLErrorDomain {
                return String(localized: "Network connection failed. Check internet and retry.")
            }
            return error.localizedDescription
        }
    }
}
