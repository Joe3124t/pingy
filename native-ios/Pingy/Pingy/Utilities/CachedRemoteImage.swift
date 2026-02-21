import CryptoKit
import Foundation
import SwiftUI
import UIKit

actor RemoteImageStore {
    static let shared = RemoteImageStore()

    private let fileManager = FileManager.default
    private let memoryCache = NSCache<NSString, UIImage>()
    private let cacheDirectoryName = "PingyRemoteImageCache"

    func fetchImage(for url: URL) async -> UIImage? {
        let key = cacheKey(for: url)
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        if let diskImage = loadFromDisk(cacheKey: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        if url.isFileURL {
            guard let localImage = UIImage(contentsOfFile: url.path) else {
                return nil
            }
            memoryCache.setObject(localImage, forKey: key as NSString)
            return localImage
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ... 299 ~= httpResponse.statusCode,
                  let image = UIImage(data: data)
            else {
                return nil
            }

            memoryCache.setObject(image, forKey: key as NSString)
            saveToDisk(data: data, cacheKey: key)
            return image
        } catch {
            return nil
        }
    }

    func primeImage(data: Data, for url: URL) async {
        let key = cacheKey(for: url)
        guard let image = UIImage(data: data) else {
            return
        }
        memoryCache.setObject(image, forKey: key as NSString)
        saveToDisk(data: data, cacheKey: key)
    }

    private func cacheKey(for url: URL) -> String {
        if url.isFileURL {
            return "file://\(url.path)"
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    private func cacheFileURL(for cacheKey: String) -> URL? {
        guard let cacheDirectory = cacheDirectoryURL() else {
            return nil
        }
        let fileName = SHA256.hash(data: Data(cacheKey.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(fileName).appendingPathExtension("img")
    }

    private func cacheDirectoryURL() -> URL? {
        guard let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = baseURL.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                AppLogger.error("Failed to create remote image cache directory: \(error.localizedDescription)")
                return nil
            }
        }
        return directory
    }

    private func loadFromDisk(cacheKey: String) -> UIImage? {
        guard let fileURL = cacheFileURL(for: cacheKey),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data)
        else {
            return nil
        }
        return image
    }

    private func saveToDisk(data: Data, cacheKey: String) {
        guard let fileURL = cacheFileURL(for: cacheKey) else {
            return
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.error("Failed to save image cache: \(error.localizedDescription)")
        }
    }
}

struct CachedRemoteImage<Content: View, Placeholder: View, Failure: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failure: () -> Failure

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else if loadFailed {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString ?? "none") {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            image = nil
            loadFailed = true
            return
        }

        loadFailed = false
        let fetched = await RemoteImageStore.shared.fetchImage(for: url)
        image = fetched
        loadFailed = fetched == nil
    }
}
