import PhotosUI
import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: MessengerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var bio = ""
    @State private var showOnline = true
    @State private var readReceipts = true
    @State private var avatarItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section("Profile") {
                HStack(spacing: 14) {
                    AvatarView(url: viewModel.currentUserSettings?.avatarUrl, fallback: viewModel.currentUserSettings?.username ?? "U")
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Label("Change avatar", systemImage: "photo")
                    }
                }

                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(2 ... 6)

                Button("Save profile") {
                    Task { await viewModel.saveProfile(username: username, bio: bio) }
                }
            }

            Section("Privacy") {
                Toggle("Show online status", isOn: $showOnline)
                Toggle("Read receipts", isOn: $readReceipts)

                Button("Save privacy") {
                    Task { await viewModel.savePrivacy(showOnline: showOnline, readReceipts: readReceipts) }
                }
            }
        }
        .navigationTitle("My Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            username = viewModel.currentUserSettings?.username ?? ""
            bio = viewModel.currentUserSettings?.bio ?? ""
            showOnline = viewModel.currentUserSettings?.showOnlineStatus ?? true
            readReceipts = viewModel.currentUserSettings?.readReceiptsEnabled ?? true
        }
        .onChange(of: avatarItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await viewModel.uploadAvatar(data)
                }
                avatarItem = nil
            }
        }
    }
}
