import CoreGraphics
import Foundation
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
              let image = UIImage(data: data)
        else {
            return nil
        }

        let format = detectImageFormat(from: data)
        let mimeType = mimeType(for: format)
        let dimensions = imageDimensions(image: image)

        let optimizedImage = resizedImage(image, maxDimension: 1700)
        let hdImage = resizedImage(image, maxDimension: 3200)

        guard let optimizedData = encode(image: optimizedImage, preferredFormat: format, quality: 0.72),
              let hdData = encode(image: hdImage, preferredFormat: format, quality: 0.92)
        else {
            return nil
        }

        let fileName = "media-\(UUID().uuidString).\(fileExtension(for: format))"

        return MediaComposerItem(
            previewImage: image,
            originalData: data,
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

    private func imageDimensions(image: UIImage) -> (width: Int, height: Int) {
        let size = image.size
        let scale = image.scale
        return (
            width: max(1, Int((size.width * scale).rounded())),
            height: max(1, Int((size.height * scale).rounded()))
        )
    }

    private func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let originalSize = image.size
        let maxSide = max(originalSize.width, originalSize.height)
        guard maxSide > maxDimension else {
            return image
        }

        let scale = maxDimension / maxSide
        let target = CGSize(
            width: max(1, (originalSize.width * scale).rounded()),
            height: max(1, (originalSize.height * scale).rounded())
        )

        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func encode(image: UIImage, preferredFormat: String, quality: CGFloat) -> Data? {
        if preferredFormat.uppercased() == "PNG", let pngData = image.pngData() {
            return pngData
        }
        return image.jpegData(compressionQuality: quality)
    }
}
