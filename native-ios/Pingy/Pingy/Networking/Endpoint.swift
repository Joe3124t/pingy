import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    var queryItems: [URLQueryItem]
    var headers: [String: String]
    var body: Data?

    init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }
}

extension Endpoint {
    static func json<T: Encodable>(
        path: String,
        method: HTTPMethod,
        payload: T,
        queryItems: [URLQueryItem] = []
    ) throws -> Endpoint {
        let encoder = JSONEncoder()
        let body = try encoder.encode(payload)
        var endpoint = Endpoint(path: path, method: method, queryItems: queryItems, body: body)
        endpoint.headers["Content-Type"] = "application/json"
        endpoint.headers["Accept"] = "application/json"
        return endpoint
    }
}
