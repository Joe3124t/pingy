import Foundation

actor CallLogService {
    static let shared = CallLogService()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "pingy.v3.calls."

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func list(for userID: String) -> [CallLogEntry] {
        guard let data = defaults.data(forKey: keyPrefix + userID) else { return [] }
        let entries = (try? decoder.decode([CallLogEntry].self, from: data)) ?? []
        return entries.sorted(by: { $0.createdAt > $1.createdAt })
    }

    func append(_ entry: CallLogEntry, for userID: String) {
        var entries = list(for: userID)
        entries.insert(entry, at: 0)
        let limited = Array(entries.prefix(200))
        guard let data = try? encoder.encode(limited) else { return }
        defaults.set(data, forKey: keyPrefix + userID)
    }

    func clear(for userID: String) {
        defaults.removeObject(forKey: keyPrefix + userID)
    }
}
