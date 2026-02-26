import PhotosUI
import SwiftUI
import UIKit

struct ContactChatThemeView: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPresetID: String?
    @State private var blurIntensity: Double = 0
    @State private var isApplying = false
    @State private var wallpaperItem: PhotosPickerItem?

    private let presets: [Preset] = [
        Preset(
            id: "ocean",
            title: "Ocean",
            start: UIColor(red: 0.05, green: 0.35, blue: 0.54, alpha: 1),
            end: UIColor(red: 0.03, green: 0.63, blue: 0.76, alpha: 1)
        ),
        Preset(
            id: "night",
            title: "Night",
            start: UIColor(red: 0.08, green: 0.09, blue: 0.17, alpha: 1),
            end: UIColor(red: 0.22, green: 0.24, blue: 0.37, alpha: 1)
        ),
        Preset(
            id: "sunset",
            title: "Sunset",
            start: UIColor(red: 0.80, green: 0.32, blue: 0.20, alpha: 1),
            end: UIColor(red: 0.94, green: 0.62, blue: 0.22, alpha: 1)
        ),
        Preset(
            id: "forest",
            title: "Forest",
            start: UIColor(red: 0.07, green: 0.39, blue: 0.29, alpha: 1),
            end: UIColor(red: 0.16, green: 0.57, blue: 0.36, alpha: 1)
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PingySpacing.md) {
                Text("Themes")
                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PingySpacing.sm) {
                    ForEach(presets) { preset in
                        themeCard(for: preset)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Wallpaper blur")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)

                    Slider(value: $blurIntensity, in: 0 ... 20, step: 1)
                        .tint(PingyTheme.primaryStrong)

                    Text(blurIntensity == 0
                        ? "Off"
                        : "Intensity: \(Int(blurIntensity))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                }
                .pingyCard()

                PhotosPicker(selection: $wallpaperItem, matching: .images) {
                    Label("Upload custom wallpaper", systemImage: "photo")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.primaryStrong)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .buttonStyle(PingyPressableButtonStyle())
                .pingyCard()

                Button {
                    Task { await resetThemeToDefault() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .bold))
                        Text("Reset to default")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(PingyTheme.primaryStrong)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(PingyPressableButtonStyle())
                .pingyCard()
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("Chat theme")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PingyPressableButtonStyle())
                .disabled(isApplying)
            }
        }
        .overlay {
            if isApplying {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("Applying theme...")
                    .padding(14)
                    .background(PingyTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous))
            }
        }
        .onAppear {
            selectedPresetID = nil
            blurIntensity = Double(max(0, min(20, conversation.blurIntensity)))
            if viewModel.selectedConversationID != conversation.conversationId {
                Task { await viewModel.selectConversation(conversation.conversationId) }
            }
        }
        .onChange(of: wallpaperItem) { newValue in
            guard let newValue else { return }
            Task {
                defer {
                    Task { @MainActor in
                        wallpaperItem = nil
                    }
                }

                guard let data = try? await newValue.loadTransferable(type: Data.self),
                      !data.isEmpty
                else {
                    await MainActor.run {
                        viewModel.showTransientNotice(
                            "Couldn't read selected wallpaper image.",
                            style: .error
                        )
                    }
                    return
                }

                let contentType = newValue.supportedContentTypes.first
                let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
                let mimeType = contentType?.preferredMIMEType ?? "image/jpeg"
                await applyWallpaper(
                    imageData: data,
                    fileName: "chat-theme-custom-\(UUID().uuidString).\(fileExtension)",
                    mimeType: mimeType,
                    announcement: "Theme changed to a custom wallpaper."
                )
            }
        }
    }

    private func themeCard(for preset: Preset) -> some View {
        Button {
            Task { await applyPreset(preset) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: preset.start), Color(uiColor: preset.end)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 122)

                HStack {
                    Text(preset.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    if selectedPresetID == preset.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous)
                    .stroke(
                        selectedPresetID == preset.id ? Color.white.opacity(0.92) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PingyPressableButtonStyle())
        .disabled(isApplying)
    }

    private func applyPreset(_ preset: Preset) async {
        guard !isApplying else { return }
        guard let data = generateWallpaperData(from: preset) else {
            viewModel.showTransientNotice("Couldn't generate wallpaper preset.", style: .error)
            return
        }

        await applyWallpaper(
            imageData: data,
            fileName: "chat-theme-\(preset.id).jpg",
            mimeType: "image/jpeg",
            announcement: "Theme changed to \(preset.title).",
            selectedPreset: preset.id
        )
    }

    private func applyWallpaper(
        imageData: Data,
        fileName: String,
        mimeType: String,
        announcement: String,
        selectedPreset: String? = nil
    ) async {
        await MainActor.run { isApplying = true }
        let applied = await viewModel.uploadConversationWallpaper(
            imageData: imageData,
            fileName: fileName,
            mimeType: mimeType,
            blurIntensity: Int(blurIntensity.rounded())
        )
        await MainActor.run { isApplying = false }

        guard applied else { return }

        await MainActor.run {
            selectedPresetID = selectedPreset
        }

        await viewModel.sendText(announcement)
    }

    private func resetThemeToDefault() async {
        guard !isApplying else { return }
        isApplying = true
        let reset = await viewModel.resetConversationWallpaper()
        isApplying = false

        guard reset else { return }

        selectedPresetID = nil
        blurIntensity = 0
        await viewModel.sendText("Theme reset to default.")
    }

    private func generateWallpaperData(from preset: Preset) -> Data? {
        let size = CGSize(width: 1200, height: 2600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [preset.start.cgColor, preset.end.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else {
                return
            }

            let start = CGPoint(x: 0, y: 0)
            let end = CGPoint(x: size.width, y: size.height)
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: start,
                end: end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        return image.jpegData(compressionQuality: 0.92)
    }
}

private struct Preset: Identifiable, Equatable {
    let id: String
    let title: String
    let start: UIColor
    let end: UIColor
}
