import Foundation

protocol AuthorizedRequester: AnyObject {
    func authorizedRequest<T: Decodable>(_ endpoint: Endpoint, as: T.Type) async throws -> T
    func authorizedNoContent(_ endpoint: Endpoint) async throws
    func authorizedRawData(_ endpoint: Endpoint) async throws -> Data
}
