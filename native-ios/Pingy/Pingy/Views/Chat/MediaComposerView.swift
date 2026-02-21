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
        configuration.preferredAssetRepresentationMode = .current

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
            picker.dismiss(animated: true) {
                if results.isEmpty {
                    self.onCancel()
                } else {
                    self.onFinish(results)
                }
            }
        }
    }
}

struct MediaComposerView: View {
    let items: [MediaComposerItem]
    let recipientName: String
    let onClose: () -> Void
    let onSend: (_ items: [MediaComposerItem], _ caption: String, _ hdEnabled: Bool) -> Void

    @State private var selectedIndex = 0
    @State private var caption = ""
    @State private var hdEnabled = false

    var body: some View {
        ZStack {
            VisualEffectBlur(style: .systemUltraThinMaterialDark)
                .ignoresSafeArea()

            Color.black.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                mediaPreview
                metadataPanel
                thumbnailsStrip
                composerBar
            }
        }
    }

    private var selectedItem: MediaComposerItem {
        let safeIndex = min(max(0, selectedIndex), max(0, items.count - 1))
        return items[safeIndex]
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
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

            toolbarIcon("crop")
            toolbarIcon("pencil.tip")
            toolbarIcon("textformat")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var mediaPreview: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
            Text("\(selectedItem.resolutionLabel) • \(selectedItem.format)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))

            Text(
                "Original \(formatBytes(selectedItem.originalSizeBytes))  •  Optimized \(formatBytes(selectedItem.optimizedSizeBytes))  •  Est. upload \(formatBytes(selectedItem.estimatedUploadSizeBytes(hdEnabled: hdEnabled)))"
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
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
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
                    PingyHaptics.softTap()
                    onSend(items, caption, hdEnabled)
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

    private func toolbarIcon(_ systemName: String) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(PingyPressableButtonStyle())
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
