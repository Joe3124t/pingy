import PencilKit
import PhotosUI
import SwiftUI
import UIKit

struct NativeMediaPickerView: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onCancel: () -> Void
    let onFinish: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .compatible

        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onFinish: onFinish)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onCancel: () -> Void
        private let onFinish: ([PHPickerResult]) -> Void

        init(onCancel: @escaping () -> Void, onFinish: @escaping ([PHPickerResult]) -> Void) {
            self.onCancel = onCancel
            self.onFinish = onFinish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty {
                onCancel()
            } else {
                onFinish(results)
            }
        }
    }
}

struct MediaComposerView: View {
    private let originalItems: [MediaComposerItem]
    private let recipientName: String
    private let onClose: () -> Void
    private let onSend: (_ items: [MediaComposerItem], _ caption: String, _ hdEnabled: Bool) -> Void

    @State private var editableItems: [MediaComposerItem]
    @State private var selectedIndex = 0
    @State private var caption = ""
    @State private var hdEnabled = false
    @State private var isCropDialogPresented = false
    @State private var isTextOverlayPromptPresented = false
    @State private var pendingOverlayText = ""
    @State private var isMarkupEditorPresented = false
    @State private var markupSeedImage: UIImage?

    init(
        items: [MediaComposerItem],
        recipientName: String,
        onClose: @escaping () -> Void,
        onSend: @escaping (_ items: [MediaComposerItem], _ caption: String, _ hdEnabled: Bool) -> Void
    ) {
        self.originalItems = items
        self.recipientName = recipientName
        self.onClose = onClose
        self.onSend = onSend
        _editableItems = State(initialValue: items)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VisualEffectBlur(style: .systemUltraThinMaterialDark)
                    .ignoresSafeArea()

                Color.black.opacity(0.9)
                    .ignoresSafeArea()

                if editableItems.isEmpty {
                    VStack(spacing: 14) {
                        Text("No media selected")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                        Button("Close") {
                            onClose()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 0) {
                        topBar
                        mediaPreview
                        metadataPanel
                        thumbnailsStrip
                        composerBar
                    }
                    .padding(.top, max(proxy.safeAreaInsets.top, 10))
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8))
                }
            }
        }
        .confirmationDialog("Crop", isPresented: $isCropDialogPresented, titleVisibility: .visible) {
            Button("Square") { applyCenteredCrop(aspectRatio: 1.0) }
            Button("Portrait 4:5") { applyCenteredCrop(aspectRatio: 4.0 / 5.0) }
            Button("Landscape 16:9") { applyCenteredCrop(aspectRatio: 16.0 / 9.0) }
            Button("Reset image") { restoreSelectedFromOriginal() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Add text overlay", isPresented: $isTextOverlayPromptPresented) {
            TextField("Text", text: $pendingOverlayText)
            Button("Apply") {
                applyTextOverlay(pendingOverlayText)
                pendingOverlayText = ""
            }
            Button("Cancel", role: .cancel) {
                pendingOverlayText = ""
            }
        } message: {
            Text("Text will be drawn on the selected image.")
        }
        .fullScreenCover(isPresented: $isMarkupEditorPresented) {
            if let markupSeedImage {
                MarkupEditorSheet(
                    image: markupSeedImage,
                    onCancel: {
                        isMarkupEditorPresented = false
                        self.markupSeedImage = nil
                    },
                    onSave: { editedImage in
                        updateSelectedItem(with: editedImage)
                        isMarkupEditorPresented = false
                        self.markupSeedImage = nil
                    }
                )
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }

    private var selectedItem: MediaComposerItem? {
        guard !editableItems.isEmpty else { return nil }
        let safeIndex = min(max(0, selectedIndex), max(0, editableItems.count - 1))
        return editableItems[safeIndex]
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(PingyPressableButtonStyle())

            Spacer()

            Toggle(isOn: $hdEnabled) {
                Text("HD")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.button)
            .buttonStyle(.borderedProminent)
            .tint(hdEnabled ? PingyTheme.primaryStrong : Color.white.opacity(0.2))

            toolbarIcon("crop", action: {
                isCropDialogPresented = true
            })
            toolbarIcon("pencil.tip", action: {
                guard let item = selectedItem else { return }
                let image = UIImage(data: item.hdData) ?? item.previewImage
                markupSeedImage = image
                isMarkupEditorPresented = true
            })
            toolbarIcon("textformat", action: {
                pendingOverlayText = ""
                isTextOverlayPromptPresented = true
            })
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var mediaPreview: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(editableItems.enumerated()), id: \.element.id) { index, item in
                Image(uiImage: item.previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedIndex)
    }

    private var metadataPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(selectedItem?.resolutionLabel ?? "--") | \(selectedItem?.format ?? "--")")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))

            Text(
                "Original \(formatBytes(selectedItem?.originalSizeBytes ?? 0)) | Optimized \(formatBytes(selectedItem?.optimizedSizeBytes ?? 0)) | Est. upload \(formatBytes(selectedItem?.estimatedUploadSizeBytes(hdEnabled: hdEnabled) ?? 0))"
            )
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.78))
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var thumbnailsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(editableItems.enumerated()), id: \.element.id) { index, item in
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                            selectedIndex = index
                        }
                    } label: {
                        Image(uiImage: item.previewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        selectedIndex == index ? PingyTheme.primaryStrong : Color.white.opacity(0.2),
                                        lineWidth: selectedIndex == index ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To \(recipientName)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.84))

            HStack(spacing: 8) {
                TextField("Add a caption...", text: $caption, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .lineLimit(1 ... 4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    guard !editableItems.isEmpty else { return }
                    PingyHaptics.softTap()
                    onSend(editableItems, caption, hdEnabled)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(PingyTheme.primaryStrong)
                        .clipShape(Circle())
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.black.opacity(0.5))
    }

    private func toolbarIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(PingyPressableButtonStyle())
    }

    private func applyCenteredCrop(aspectRatio: CGFloat) {
        guard let item = selectedItem else { return }
        let sourceImage = UIImage(data: item.hdData) ?? item.previewImage
        let normalized = sourceImage.pingyNormalizedOrientation()
        guard let cgImage = normalized.cgImage else { return }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        var cropWidth = imageWidth
        var cropHeight = cropWidth / max(aspectRatio, 0.01)

        if cropHeight > imageHeight {
            cropHeight = imageHeight
            cropWidth = cropHeight * max(aspectRatio, 0.01)
        }

        let cropX = max(0, (imageWidth - cropWidth) * 0.5)
        let cropY = max(0, (imageHeight - cropHeight) * 0.5)
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight).integral

        guard let croppedCG = cgImage.cropping(to: cropRect) else { return }
        let croppedImage = UIImage(cgImage: croppedCG, scale: normalized.scale, orientation: .up)
        updateSelectedItem(with: croppedImage)
    }

    private func applyTextOverlay(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let item = selectedItem else { return }

        let sourceImage = UIImage(data: item.hdData) ?? item.previewImage
        let baseImage = sourceImage.pingyNormalizedOrientation()
        let size = baseImage.size

        let renderer = UIGraphicsImageRenderer(size: size)
        let result = renderer.image { context in
            baseImage.draw(in: CGRect(origin: .zero, size: size))

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let fontSize = max(26, size.width * 0.07)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black.withAlphaComponent(0.55),
                .strokeWidth: -2.0,
                .paragraphStyle: paragraphStyle,
            ]

            let rect = CGRect(
                x: size.width * 0.1,
                y: size.height * 0.72,
                width: size.width * 0.8,
                height: size.height * 0.22
            )
            (trimmed as NSString).draw(in: rect, withAttributes: attributes)
        }

        updateSelectedItem(with: result)
    }

    private func restoreSelectedFromOriginal() {
        guard selectedIndex >= 0, selectedIndex < originalItems.count else { return }
        guard selectedIndex < editableItems.count else { return }
        editableItems[selectedIndex] = originalItems[selectedIndex]
    }

    private func updateSelectedItem(with image: UIImage) {
        guard selectedIndex >= 0, selectedIndex < editableItems.count else { return }
        guard let current = selectedItem else { return }
        guard let updated = makeComposerItem(from: image, basedOn: current) else { return }
        editableItems[selectedIndex] = updated
    }

    private func makeComposerItem(from image: UIImage, basedOn item: MediaComposerItem) -> MediaComposerItem? {
        let normalized = image.pingyNormalizedOrientation()
        let preview = normalized.pingyResized(maxDimension: 1800)
        let optimizedImage = normalized.pingyResized(maxDimension: 1500)
        let hdImage = normalized.pingyResized(maxDimension: 2600)

        let optimizedData = encodeImage(optimizedImage, format: item.format, quality: 0.72)
        let hdCandidate = encodeImage(hdImage, format: item.format, quality: 0.92)

        guard let optimizedData else { return nil }
        let hdData = (hdCandidate?.isEmpty == false) ? (hdCandidate ?? optimizedData) : optimizedData
        let effectiveHdData = hdData.count > 8_000_000 ? optimizedData : hdData

        return MediaComposerItem(
            id: item.id,
            previewImage: preview,
            originalSizeBytes: max(effectiveHdData.count, optimizedData.count),
            optimizedData: optimizedData,
            hdData: effectiveHdData,
            mimeType: item.mimeType,
            format: item.format,
            pixelWidth: Int(max(normalized.size.width, 1)),
            pixelHeight: Int(max(normalized.size.height, 1)),
            source: item.source,
            fileName: item.fileName
        )
    }

    private func encodeImage(_ image: UIImage, format: String, quality: CGFloat) -> Data? {
        if format.uppercased() == "PNG" {
            return image.pngData()
        }
        return image.jpegData(compressionQuality: quality)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

private struct VisualEffectBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

private struct MarkupEditorSheet: UIViewControllerRepresentable {
    let image: UIImage
    let onCancel: () -> Void
    let onSave: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let editor = MarkupEditorViewController(
            image: image,
            onCancel: onCancel,
            onSave: onSave
        )
        let nav = UINavigationController(rootViewController: editor)
        nav.navigationBar.prefersLargeTitles = false
        nav.modalPresentationStyle = .fullScreen
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

private final class MarkupEditorViewController: UIViewController, PKCanvasViewDelegate {
    private let baseImage: UIImage
    private let onCancelAction: () -> Void
    private let onSaveAction: (UIImage) -> Void

    private let imageView = UIImageView()
    private let canvasView = PKCanvasView()
    private var toolPicker: PKToolPicker?

    init(
        image: UIImage,
        onCancel: @escaping () -> Void,
        onSave: @escaping (UIImage) -> Void
    ) {
        self.baseImage = image.pingyNormalizedOrientation()
        onCancelAction = onCancel
        onSaveAction = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        imageView.image = baseImage
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        canvasView.backgroundColor = .clear
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = self
        canvasView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(imageView)
        view.addSubview(canvasView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            canvasView.topAnchor.constraint(equalTo: imageView.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
        ])

        navigationItem.title = "Markup"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let window = view.window else { return }

        let picker = PKToolPicker.shared(for: window)
        picker?.setVisible(true, forFirstResponder: canvasView)
        picker?.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        toolPicker = picker
    }

    @objc private func cancelTapped() {
        onCancelAction()
    }

    @objc private func saveTapped() {
        let rendered = renderComposedImage()
        onSaveAction(rendered)
    }

    private func renderComposedImage() -> UIImage {
        let targetSize = baseImage.size
        let drawingImage = canvasView.drawing.image(from: canvasView.bounds, scale: 1.0)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: targetSize))
            drawingImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension UIImage {
    func pingyNormalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func pingyResized(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return self }

        let scaleRatio = maxDimension / longestSide
        let newSize = CGSize(
            width: max(1, size.width * scaleRatio),
            height: max(1, size.height * scaleRatio)
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
