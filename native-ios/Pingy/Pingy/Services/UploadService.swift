import Foundation

final class UploadService {
    func uploadMediaBatch(
        items: [MediaComposerItem],
        caption: String,
        hdEnabled: Bool,
        send: @escaping (_ item: MediaComposerItem, _ data: Data, _ caption: String?) async -> Void
    ) async {
        guard !items.isEmpty else { return }

        let normalizedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in items {
            await send(
                item,
                item.uploadData(hdEnabled: hdEnabled),
                normalizedCaption.isEmpty ? nil : normalizedCaption
            )
        }
    }
}
