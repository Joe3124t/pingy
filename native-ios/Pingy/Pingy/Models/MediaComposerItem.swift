import Foundation
import UIKit

enum MediaUploadSource: String, Codable {
    case gallery
    case camera
}

struct MediaComposerItem: Identifiable {
    let id: UUID
    let previewImage: UIImage
    let originalSizeBytes: Int
    let optimizedData: Data
    let hdData: Data
    let mimeType: String
    let format: String
    let pixelWidth: Int
    let pixelHeight: Int
    let source: MediaUploadSource
    let fileName: String

    init(
        id: UUID = UUID(),
        previewImage: UIImage,
        originalSizeBytes: Int,
        optimizedData: Data,
        hdData: Data,
        mimeType: String,
        format: String,
        pixelWidth: Int,
        pixelHeight: Int,
        source: MediaUploadSource,
        fileName: String
    ) {
        self.id = id
        self.previewImage = previewImage
        self.originalSizeBytes = originalSizeBytes
        self.optimizedData = optimizedData
        self.hdData = hdData
        self.mimeType = mimeType
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.source = source
        self.fileName = fileName
    }

    var optimizedSizeBytes: Int {
        optimizedData.count
    }

    var hdSizeBytes: Int {
        hdData.count
    }

    var resolutionLabel: String {
        "\(pixelWidth)x\(pixelHeight)"
    }

    func uploadData(hdEnabled: Bool) -> Data {
        hdEnabled ? hdData : optimizedData
    }

    func estimatedUploadSizeBytes(hdEnabled: Bool) -> Int {
        uploadData(hdEnabled: hdEnabled).count
    }
}
