import Foundation

struct ContactSearchResult: Identifiable, Equatable {
    let id: String
    let user: User
    let contactName: String
}

struct ContactHashEntry: Encodable {
    let hash: String
    let label: String
}

struct ContactSyncRequest: Encodable {
    let contacts: [ContactHashEntry]
}

struct ContactSyncMatch: Decodable {
    let hash: String
    let contactName: String?
    let user: User
}

struct ContactSyncResponse: Decodable {
    let matches: [ContactSyncMatch]
}
