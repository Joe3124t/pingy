import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatSettingsView: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss

    @State private var blurIntensity: Double = 0
    @State private var isBlurEnabled = false
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var showDeleteForEveryoneConfirmation = false
    @State private var showDeleteForMeConfirmation = false
    @State private var showBlockConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                wallpaperCard
                safetyCard
                deleteCard
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle("Chat settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .onAppear {
            blurIntensity = max(1, Double(conversation.blurIntensity == 0 ? 6 : conversation.blurIntensity))
            // Blur is opt-in; new wallpaper uploads default to non-blurred unless user enables it.
            isBlurEnabled = false
        }
        .onChange(of: wallpaperItem) { newValue in
            guard let newValue else { return }
            Task {
                let contentType = newValue.supportedContentTypes.first
                let extensionPart = contentType?.preferredFilenameExtension ?? "jpg"
                let mimeType = contentType?.preferredMIMEType ?? "image/jpeg"

                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await viewModel.uploadConversationWallpaper(
                        imageData: data,
                        fileName: "chat-wallpaper-\(UUID().uuidString).\(extensionPart)",
                        mimeType: mimeType,
                        blurIntensity: isBlurEnabled ? Int(blurIntensity) : 0
                    )
                }
                wallpaperItem = nil
            }
        }
        .confirmationDialog(
            "Delete this chat only for your account?",
            isPresented: $showDeleteForMeConfirmation
        ) {
            Button("Delete for me", role: .destructive) {
                Task {
                    await viewModel.deleteSelectedConversation(forEveryone: false)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete chat history for both users?",
            isPresented: $showDeleteForEveryoneConfirmation
        ) {
            Button("Delete for both", role: .destructive) {
                Task {
                    await viewModel.deleteSelectedConversation(forEveryone: true)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Block this user?",
            isPresented: $showBlockConfirmation
        ) {
            Button("Block user", role: .destructive) {
                Task {
                    await viewModel.blockSelectedUser()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var wallpaperCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Conversation wallpaper")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Text("Wallpaper stays fixed while messages scroll over it.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)

            Toggle("Blur wallpaper", isOn: $isBlurEnabled)
                .tint(PingyTheme.primary)

            if isBlurEnabled {
                Slider(value: $blurIntensity, in: 1 ... 20, step: 1)
                    .tint(PingyTheme.primary)

                Text("Blur intensity: \(Int(blurIntensity))")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            } else {
                Text("Wallpaper blur is off.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            }

            Button("Apply blur setting") {
                Task {
                    await viewModel.updateConversationWallpaperBlur(
                        isBlurEnabled ? Int(blurIntensity) : 0
                    )
                }
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .buttonStyle(PingyPressableButtonStyle())
            .foregroundStyle(PingyTheme.primaryStrong)

            PhotosPicker(selection: $wallpaperItem, matching: .images) {
                Label("Upload wallpaper", systemImage: "photo")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.primaryStrong)
            }
            .buttonStyle(PingyPressableButtonStyle())

            Button("Reset wallpaper") {
                Task {
                    await viewModel.resetConversationWallpaper()
                }
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .buttonStyle(PingyPressableButtonStyle())
            .foregroundStyle(PingyTheme.primaryStrong)
        }
        .pingyCard()
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Privacy & Safety")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            if conversation.blockedByMe {
                Text("You blocked this user.")
                    .foregroundStyle(PingyTheme.textSecondary)
            } else if conversation.blockedByParticipant {
                Text("This user blocked you.")
                    .foregroundStyle(PingyTheme.textSecondary)
            } else {
                Button("Block user", role: .destructive) {
                    showBlockConfirmation = true
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .pingyCard()
    }

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text("Conversation")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Button("Delete chat for me", role: .destructive) {
                showDeleteForMeConfirmation = true
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .buttonStyle(PingyPressableButtonStyle())

            Button("Delete for both users", role: .destructive) {
                showDeleteForEveryoneConfirmation = true
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }
}
