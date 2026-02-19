import PhotosUI
import SwiftUI

struct ChatSettingsView: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss

    @State private var blurIntensity: Double = 0
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var showDeleteForEveryoneConfirmation = false
    @State private var showDeleteForMeConfirmation = false
    @State private var showBlockConfirmation = false

    var body: some View {
        Form {
            Section("Conversation wallpaper") {
                Text("Wallpaper stays fixed while messages scroll over it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Slider(value: $blurIntensity, in: 0 ... 20, step: 1) {
                    Text("Blur")
                }
                Text("Blur intensity: \(Int(blurIntensity))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $wallpaperItem, matching: .images) {
                    Label("Upload wallpaper", systemImage: "photo")
                }

                Button("Reset wallpaper") {
                    Task {
                        await viewModel.resetConversationWallpaper()
                    }
                }
            }

            Section("Privacy and safety") {
                if conversation.blockedByMe {
                    Text("You blocked this user.")
                        .foregroundStyle(.secondary)
                } else if conversation.blockedByParticipant {
                    Text("This user blocked you.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Block user", role: .destructive) {
                        showBlockConfirmation = true
                    }
                }
            }

            Section("Conversation") {
                Button("Delete chat for me", role: .destructive) {
                    showDeleteForMeConfirmation = true
                }

                Button("Delete for both users", role: .destructive) {
                    showDeleteForEveryoneConfirmation = true
                }
            }
        }
        .navigationTitle("Chat settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .onAppear {
            blurIntensity = Double(conversation.blurIntensity)
        }
        .onChange(of: wallpaperItem) { newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await viewModel.uploadConversationWallpaper(
                        imageData: data,
                        blurIntensity: Int(blurIntensity)
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
}
