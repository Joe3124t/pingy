import Foundation

@MainActor
final class NetworkUsageStore: ObservableObject {
    static let shared = NetworkUsageStore()

    @Published private(set) var uploadedBytes: Int64
    @Published private(set) var downloadedBytes: Int64

    private let defaults = UserDefaults.standard
    private let uploadedKey = "pingy.network.uploadedBytes"
    private let downloadedKey = "pingy.network.downloadedBytes"

    private init() {
        uploadedBytes = Int64(defaults.integer(forKey: uploadedKey))
        downloadedBytes = Int64(defaults.integer(forKey: downloadedKey))
    }

    var totalBytes: Int64 {
        uploadedBytes + downloadedBytes
    }

    func track(uploaded: Int64, downloaded: Int64) {
        if uploaded > 0 {
            uploadedBytes += uploaded
        }
        if downloaded > 0 {
            downloadedBytes += downloaded
        }

        defaults.set(Int(uploadedBytes), forKey: uploadedKey)
        defaults.set(Int(downloadedBytes), forKey: downloadedKey)
    }

    func reset() {
        uploadedBytes = 0
        downloadedBytes = 0
        defaults.set(0, forKey: uploadedKey)
        defaults.set(0, forKey: downloadedKey)
    }
}
