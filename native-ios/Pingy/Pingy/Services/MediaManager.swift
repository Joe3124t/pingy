import CoreGraphics
import Foundation
import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers

actor MediaManager {
    func loadComposerItems(
        from results: [PHPickerResult],
        source: MediaUploadSource = .gallery
    ) async -> [MediaComposerItem] {
        var items: [MediaComposerItem] = []

        for result in results {
            if let item = await loadSingleItem(from: result, source: source) {
                items.append(item)
            }
        }

        return items
    }

    private func loadSingleItem(
        from result: PHPickerResult,
        source: MediaUploadSource
    ) async -> MediaComposerItem? {
        let provider = result.itemProvider
        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
            if let type = UTType(identifier) {
                return type.conforms(to: .image)
            }
            return false
        } ?? UTType.image.identifier

        guard let data = await loadData(from: provider, typeIdentifier: typeIdentifier),
              !data.isEmpty
        else {
            return nil
        }

        // Defensive limit for stability on older devices.
        guard data.count <= 40_000_000 else {
            AppLogger.error("Skipped media item because source data is too large: \(data.count)")
            return nil
        }

        guard let previewImage = downsampledImage(from: data, maxPixelSize: 2200) else {
            return nil
        }

        let format = detectImageFormat(from: data)
        let mimeType = mimeType(for: format)
        let dimensions = imageDimensions(from: data)

        let optimizedImage = downsampledImage(from: data, maxPixelSize: 1700) ?? previewImage
        let hdImage = downsampledImage(from: data, maxPixelSize: 3200) ?? optimizedImage

        guard let optimizedData = encode(image: optimizedImage, preferredFormat: format, quality: 0.72) else {
            return nil
        }
        let hdDataCandidate = encode(image: hdImage, preferredFormat: format, quality: 0.92) ?? optimizedData
        let hdData = hdDataCandidate.count > 8_000_000 ? optimizedData : hdDataCandidate

        let fileName = "media-\(UUID().uuidString).\(fileExtension(for: format))"

        return MediaComposerItem(
            previewImage: previewImage,
            originalSizeBytes: data.count,
            optimizedData: optimizedData,
            hdData: hdData,
            mimeType: mimeType,
            format: format,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height,
            source: source,
            fileName: fileName
        )
    }

    private func loadData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func detectImageFormat(from data: Data) -> String {
        guard let first = data.first else { return "JPEG" }
        switch first {
        case 0x89:
            return "PNG"
        case 0xFF:
            return "JPEG"
        case 0x52:
            return "WEBP"
        default:
            return "JPEG"
        }
    }

    private func mimeType(for format: String) -> String {
        switch format.uppercased() {
        case "PNG":
            return "image/png"
        case "WEBP":
            return "image/webp"
        case "HEIC":
            return "image/heic"
        default:
            return "image/jpeg"
        }
    }

    private func fileExtension(for format: String) -> String {
        switch format.uppercased() {
        case "PNG":
            return "png"
        case "WEBP":
            return "webp"
        case "HEIC":
            return "heic"
        default:
            return "jpg"
        }
    }

    private func imageDimensions(from data: Data) -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (1, 1)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 1
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 1
        return (max(width, 1), max(height, 1))
    }

    private func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: true,
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private func encode(image: UIImage, preferredFormat: String, quality: CGFloat) -> Data? {
        if preferredFormat.uppercased() == "PNG", let pngData = image.pngData() {
            return pngData
        }
        return image.jpegData(compressionQuality: quality)
    }
}
