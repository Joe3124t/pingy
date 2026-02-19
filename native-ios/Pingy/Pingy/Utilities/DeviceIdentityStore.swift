import Foundation

final class DeviceIdentityStore {
    static let shared = DeviceIdentityStore()
    private init() {}

    private let keychain = KeychainStore.shared
    private let deviceIDKey = "pingy.device.id.v2"

    func currentDeviceID() -> String {
        if let existing = try? keychain.string(for: deviceIDKey), let existing, !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try? keychain.set(created, for: deviceIDKey)
        return created
    }

    func rotateDeviceID() {
        let created = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try? keychain.set(created, for: deviceIDKey)
    }
}
