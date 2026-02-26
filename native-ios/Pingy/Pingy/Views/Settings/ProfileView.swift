import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject var viewModel: MessengerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var bio = ""
    @State private var websiteLink = ""
    @State private var socialLink = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var showSavedBadge = false

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                profileHeader
                identityCard
            }
            .padding(PingySpacing.md)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationTitle(String(localized: "My Profile"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Done")) {
                    dismiss()
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .onAppear {
            username = viewModel.currentUserSettings?.username ?? ""
            bio = viewModel.currentUserSettings?.bio ?? ""
            restoreLinks()
        }
        .onChange(of: avatarItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let optimizedData = prepareAvatarUploadData(from: data)
                    let success = await viewModel.uploadAvatar(
                        optimizedData,
                        fileName: "avatar-\(UUID().uuidString).jpg",
                        mimeType: "image/jpeg"
                    )
                    if success {
                        showSuccessBadge()
                    }
                }
                avatarItem = nil
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    AvatarView(
                        url: viewModel.currentUserSettings?.avatarUrl,
                        fallback: viewModel.currentUserSettings?.username ?? "U",
                        size: 112,
                        cornerRadius: 36
                    )

                    if viewModel.isUploadingAvatar {
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 112, height: 112)
                        ProgressView()
                            .tint(.white)
                    }
                }

                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(PingyTheme.primaryStrong)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(PingyTheme.surface, lineWidth: 3)
                        )
                }
                .buttonStyle(PingyPressableButtonStyle())
            }

            VStack(spacing: 4) {
                Text(viewModel.currentUserSettings?.username ?? String(localized: "Pingy User"))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                Text(viewModel.currentUserSettings?.phoneNumber ?? "")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textSecondary)
            }
        }
        .pingyCard()
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: PingySpacing.sm) {
            Text(String(localized: "Profile"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            labeledTextField(String(localized: "Username"), text: $username)

            infoRow(title: String(localized: "Phone number"), value: viewModel.currentUserSettings?.phoneNumber ?? "-")

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Bio"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)

                TextField(String(localized: "Add bio..."), text: $bio, axis: .vertical)
                    .lineLimit(3 ... 6)
                    .padding(12)
                    .background(PingyTheme.inputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PingyTheme.border, lineWidth: 1)
                    )
            }

            labeledTextField(String(localized: "Website"), text: $websiteLink, placeholder: String(localized: "https://..."))
            labeledTextField(String(localized: "Links"), text: $socialLink, placeholder: String(localized: "@username / profile link"))

            Button {
                Task {
                    let success = await viewModel.saveProfile(username: username, bio: bio)
                    if success {
                        persistLinks()
                        showSuccessBadge()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSavingProfile {
                        ProgressView().tint(.white)
                    }
                    Text(String(localized: "Save profile"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(PingyTheme.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PingyPressableButtonStyle())
            .disabled(viewModel.isSavingProfile)

            if showSavedBadge {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(String(localized: "Saved successfully"))
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.success)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .pingyCard()
    }

    private func labeledTextField(_ title: String, text: Binding<String>, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
            TextField(placeholder, text: text)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .padding(12)
                .background(PingyTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PingyTheme.border, lineWidth: 1)
                )
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func linksStorageKey(_ suffix: String) -> String {
        let userID = viewModel.currentUserSettings?.id ?? "default"
        return "pingy.profile.\(userID).\(suffix)"
    }

    private func restoreLinks() {
        let defaults = UserDefaults.standard
        websiteLink = defaults.string(forKey: linksStorageKey("website")) ?? ""
        socialLink = defaults.string(forKey: linksStorageKey("social")) ?? ""
    }

    private func persistLinks() {
        let defaults = UserDefaults.standard
        defaults.set(websiteLink.trimmingCharacters(in: .whitespacesAndNewlines), forKey: linksStorageKey("website"))
        defaults.set(socialLink.trimmingCharacters(in: .whitespacesAndNewlines), forKey: linksStorageKey("social"))
    }

    private func prepareAvatarUploadData(from sourceData: Data) -> Data {
        let maxUploadBytes = 4_800_000
        guard let originalImage = UIImage(data: sourceData) else {
            return sourceData
        }

        var resizedImage = originalImage.scaledDown(maxDimension: 1600)
        let qualities: [CGFloat] = [0.92, 0.84, 0.76, 0.68, 0.6, 0.52, 0.44]

        for _ in 0 ..< 4 {
            for quality in qualities {
                if let jpegData = resizedImage.jpegData(compressionQuality: quality), jpegData.count <= maxUploadBytes {
                    return jpegData
                }
            }
            resizedImage = resizedImage.scaledDown(
                maxDimension: max(900, max(resizedImage.size.width, resizedImage.size.height) * 0.82)
            )
        }

        return resizedImage.jpegData(compressionQuality: 0.35) ?? sourceData
    }

    private func showSuccessBadge() {
        PingyHaptics.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showSavedBadge = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                showSavedBadge = false
            }
        }
    }
}

private extension UIImage {
    func scaledDown(maxDimension: CGFloat) -> UIImage {
        let currentMaxDimension = max(size.width, size.height)
        guard currentMaxDimension > maxDimension else {
            return self
        }

        let scaleRatio = maxDimension / currentMaxDimension
        let targetSize = CGSize(width: size.width * scaleRatio, height: size.height * scaleRatio)
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        rendererFormat.opaque = false

        return UIGraphicsImageRenderer(size: targetSize, format: rendererFormat).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
