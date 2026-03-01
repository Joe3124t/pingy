import CryptoKit
import Foundation

final class VoiceMediaDiskCache {
    static let shared = VoiceMediaDiskCache()

    private let memory = NSCache<NSString, NSData>()
    private let queue = DispatchQueue(label: "pingy.voice.media.cache", qos: .utility)
    private let fileManager = FileManager.default
    private let maxAge: TimeInterval = 3 * 24 * 60 * 60

    private lazy var cacheDirectory: URL = {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let target = base.appendingPathComponent("pingy-voice-cache", isDirectory: true)
        try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }()

    private init() {
        memory.countLimit = 48
        memory.totalCostLimit = 24 * 1024 * 1024
    }

    func data(for url: URL, allowExpired: Bool = false) -> Data? {
        let key = cacheKey(for: url)
        return data(forCacheKey: key, allowExpired: allowExpired)
    }

    func data(forMessageID messageID: String, allowExpired: Bool = false) -> Data? {
        let key = cacheKey(forRawString: "voice-message::\(messageID)")
        return data(forCacheKey: key, allowExpired: allowExpired)
    }

    func data(forCacheKey key: String, allowExpired: Bool = false) -> Data? {
        if let cached = memory.object(forKey: key as NSString) {
            return cached as Data
        }

        let fileURL = fileURL(forKey: key)
        return queue.sync {
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
            if !allowExpired,
               let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let modified = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) > maxAge
            {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }

            guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]), !data.isEmpty else {
                return nil
            }
            memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
            return data
        }
    }

    func store(data: Data, for url: URL) {
        guard !data.isEmpty else { return }
        let key = cacheKey(for: url)
        store(data: data, forCacheKey: key)
    }

    func store(data: Data, forMessageID messageID: String) {
        guard !data.isEmpty else { return }
        let key = cacheKey(forRawString: "voice-message::\(messageID)")
        store(data: data, forCacheKey: key)
    }

    func store(data: Data, forCacheKey key: String) {
        guard !data.isEmpty else { return }
        memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        let target = fileURL(forKey: key)

        queue.async {
            do {
                try data.write(to: target, options: [.atomic])
            } catch {
                AppLogger.error("VoiceMediaDiskCache write failed: \(error.localizedDescription)")
            }
        }
    }

    private func fileURL(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent(key).appendingPathExtension("bin")
    }

    private func cacheKey(for url: URL) -> String {
        cacheKey(forRawString: url.absoluteString)
    }

    private func cacheKey(forRawString raw: String) -> String {
        let input = Data(raw.utf8)
        let digest = SHA256.hash(data: input)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
