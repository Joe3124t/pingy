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
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Session expired. Please log in again."
        case .server(_, let message):
            return message
        case .decodingError:
            return "Unable to decode server response"
        case .network(let error):
            return error.localizedDescription
        }
    }
}
