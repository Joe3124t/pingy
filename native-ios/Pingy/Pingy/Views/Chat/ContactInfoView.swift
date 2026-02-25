import SwiftUI

struct ContactInfoView: View {
    @ObservedObject var viewModel: MessengerViewModel
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss

    @State private var isMuted = false
    @State private var saveToPhotos = false
    @State private var lockChat = false
    @State private var isFavorite = false
    @State private var showBlockConfirm = false
    @State private var showClearChatConfirm = false
    @State private var showReportConfirm = false
    @State private var showAvatarPreview = false
    @State private var showEditActions = false

    private var muteKey: String {
        "pingy.chat.muted.\(conversation.conversationId)"
    }

    private var saveToPhotosKey: String {
        "pingy.chat.save-to-photos.\(conversation.conversationId)"
    }

    private var lockChatKey: String {
        "pingy.chat.locked.\(conversation.conversationId)"
    }

    private var favoriteKey: String {
        "pingy.chat.favorite.\(conversation.conversationId)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PingySpacing.md) {
                headerSection
                contactDetailsSection
                quickActionsSection
                commonGroupsSection
                mediaSection
                chatSettingsSection
                actionsSection
                dangerSection
            }
            .padding(.horizontal, PingySpacing.md)
            .padding(.bottom, 28)
        }
        .background(PingyTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(contactDisplayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
                    .lineLimit(1)
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 18, weight: .bold))
                }
                .buttonStyle(PingyPressableButtonStyle())
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showEditActions = true
                }
                    .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .onAppear {
            isMuted = UserDefaults.standard.bool(forKey: muteKey)
            saveToPhotos = UserDefaults.standard.bool(forKey: saveToPhotosKey)
            lockChat = UserDefaults.standard.bool(forKey: lockChatKey)
            isFavorite = UserDefaults.standard.bool(forKey: favoriteKey)
        }
        .onChange(of: isMuted) { UserDefaults.standard.set($0, forKey: muteKey) }
        .onChange(of: saveToPhotos) { UserDefaults.standard.set($0, forKey: saveToPhotosKey) }
        .onChange(of: lockChat) { UserDefaults.standard.set($0, forKey: lockChatKey) }
        .onChange(of: isFavorite) { UserDefaults.standard.set($0, forKey: favoriteKey) }
        .confirmationDialog("Block this contact?", isPresented: $showBlockConfirm) {
            Button("Block", role: .destructive) {
                Task {
                    await viewModel.blockSelectedUser()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear chat for your account?", isPresented: $showClearChatConfirm) {
            Button("Clear chat", role: .destructive) {
                Task {
                    await viewModel.deleteSelectedConversation(forEveryone: false)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Report this contact?", isPresented: $showReportConfirm) {
            Button("Report", role: .destructive) {
                viewModel.showTransientNotice("Report sent. Thank you.", style: .success)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Edit contact", isPresented: $showEditActions) {
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                isFavorite.toggle()
                PingyHaptics.softTap()
            }
            Button("Chat settings") {
                viewModel.isChatSettingsPresented = true
                dismiss()
            }
            Button(isMuted ? "Unmute notifications" : "Mute notifications") {
                isMuted.toggle()
                PingyHaptics.softTap()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAvatarPreview) {
            avatarPreviewSheet
        }
    }

    private var headerSection: some View {
        VStack(spacing: 14) {
            Button {
                if avatarURL != nil {
                    showAvatarPreview = true
                }
            } label: {
                AvatarView(
                    url: conversation.participantAvatarUrl,
                    fallback: contactDisplayName,
                    size: 112,
                    cornerRadius: 56
                )
            }
            .buttonStyle(PingyPressableButtonStyle())

            Text(contactDisplayName)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(contactPhoneNumber)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var contactDetailsSection: some View {
        VStack(spacing: 0) {
            sectionRow(
                icon: "person.crop.circle",
                title: "Contact details",
                action: {}
            )
        }
        .pingyCard()
    }

    private var quickActionsSection: some View {
        HStack(spacing: PingySpacing.sm) {
            quickActionButton(
                icon: "phone.fill",
                title: "Audio",
                action: {
                    PingyHaptics.softTap()
                    viewModel.startCall(from: conversation)
                }
            )

            quickActionButton(
                icon: "video.fill",
                title: "Video",
                action: {
                    PingyHaptics.softTap()
                    viewModel.showTransientNotice("Video calling is coming soon.", style: .info)
                }
            )

            quickActionButton(
                icon: "magnifyingglass",
                title: "Search",
                action: {
                    PingyHaptics.softTap()
                    viewModel.showTransientNotice("Use search from inside the chat screen.", style: .info)
                }
            )
        }
    }

    private var commonGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Groups in common")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            VStack(spacing: 0) {
                Button {
                    viewModel.showTransientNotice("Group creation flow is being expanded.", style: .info)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(PingyTheme.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(PingyTheme.surfaceAlt)
                            .clipShape(Circle())

                        Text("Create group with \(contactDisplayName)")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(PingyTheme.textPrimary)

                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PingyPressableButtonStyle())

                Divider().overlay(PingyTheme.border.opacity(0.35))

                if commonGroups.isEmpty {
                    HStack {
                        Text("No groups in common yet")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(PingyTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 14)
                } else {
                    ForEach(commonGroups, id: \.id) { group in
                        if group.id != commonGroups.first?.id {
                            Divider().overlay(PingyTheme.border.opacity(0.35))
                        }
                        Button {
                            viewModel.showTransientNotice("Group details will be available in the group module.", style: .info)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(PingyTheme.surfaceAlt)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(group.initials)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(PingyTheme.textPrimary)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.title)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(PingyTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(group.subtitle)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(PingyTheme.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                                Image(systemName: "chevron.forward")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(PingyTheme.textSecondary.opacity(0.7))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PingyPressableButtonStyle())
                    }
                }
            }
            .pingyCard()
        }
    }

    private var mediaSection: some View {
        VStack(spacing: 0) {
            sectionRow(
                icon: "photo.on.rectangle.angled",
                title: "Media, links and docs",
                detail: "\(mediaCount + linksCount + documentCount)",
                action: {}
            )

            Divider().overlay(PingyTheme.border.opacity(0.35))

            sectionRow(
                icon: "star",
                title: "Starred",
                detail: isFavorite ? "Saved" : "None",
                action: {
                    isFavorite.toggle()
                    PingyHaptics.softTap()
                }
            )
        }
        .pingyCard()
    }

    private var chatSettingsSection: some View {
        VStack(spacing: 0) {
            toggleRow(icon: "bell", title: "Notifications", isOn: $isMuted, invertMeaning: true)
            Divider().overlay(PingyTheme.border.opacity(0.35))

            sectionRow(
                icon: "paintpalette",
                title: "Chat theme",
                detail: "Default",
                action: {
                    viewModel.isChatSettingsPresented = true
                    dismiss()
                }
            )
            Divider().overlay(PingyTheme.border.opacity(0.35))

            toggleRow(icon: "square.and.arrow.down", title: "Save to Photos", isOn: $saveToPhotos)
            Divider().overlay(PingyTheme.border.opacity(0.35))

            sectionRow(
                icon: "timer",
                title: "Disappearing messages",
                detail: "Off",
                action: {
                    viewModel.showTransientNotice("Disappearing messages will be added soon.", style: .info)
                }
            )
            Divider().overlay(PingyTheme.border.opacity(0.35))

            toggleRow(icon: "lock", title: "Lock chat", isOn: $lockChat)
        }
        .pingyCard()
    }

    private var actionsSection: some View {
        VStack(spacing: 0) {
            ShareLink(item: contactShareText) {
                sectionLabel(icon: "person.crop.circle.badge.plus", title: "Share contact", tint: PingyTheme.success)
            }
            .buttonStyle(PingyPressableButtonStyle())

            Divider().overlay(PingyTheme.border.opacity(0.35))

            Button {
                isFavorite.toggle()
                PingyHaptics.softTap()
            } label: {
                sectionLabel(
                    icon: isFavorite ? "heart.slash" : "heart",
                    title: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    tint: PingyTheme.success
                )
            }
            .buttonStyle(PingyPressableButtonStyle())

            Divider().overlay(PingyTheme.border.opacity(0.35))

            ShareLink(item: exportedChatText) {
                sectionLabel(icon: "square.and.arrow.up", title: "Export chat", tint: PingyTheme.success)
            }
            .buttonStyle(PingyPressableButtonStyle())

            Divider().overlay(PingyTheme.border.opacity(0.35))

            Button {
                showClearChatConfirm = true
            } label: {
                sectionLabel(icon: "trash", title: "Clear chat", tint: PingyTheme.danger)
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private var dangerSection: some View {
        VStack(spacing: 0) {
            Button {
                showBlockConfirm = true
            } label: {
                sectionLabel(icon: "hand.raised", title: "Block \(contactDisplayName)", tint: PingyTheme.danger)
            }
            .buttonStyle(PingyPressableButtonStyle())

            Divider().overlay(PingyTheme.border.opacity(0.35))

            Button {
                showReportConfirm = true
            } label: {
                sectionLabel(icon: "exclamationmark.bubble", title: "Report \(contactDisplayName)", tint: PingyTheme.danger)
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .pingyCard()
    }

    private func quickActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(PingyTheme.success)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(PingyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous)
                    .stroke(PingyTheme.border.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PingyPressableButtonStyle())
    }

    private func sectionRow(
        icon: String,
        title: String,
        detail: String? = nil,
        tint: Color = PingyTheme.textPrimary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)

                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)

                Spacer()

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PingyTheme.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PingyTheme.textSecondary.opacity(0.75))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PingyPressableButtonStyle())
    }

    private func toggleRow(
        icon: String,
        title: String,
        isOn: Binding<Bool>,
        invertMeaning: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PingyTheme.textPrimary)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textPrimary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { invertMeaning ? !isOn.wrappedValue : isOn.wrappedValue },
                set: { isOn.wrappedValue = invertMeaning ? !$0 : $0 }
            ))
            .labelsHidden()
            .tint(PingyTheme.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 14)
    }

    private func sectionLabel(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var avatarPreviewSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(.white)
                        case .success(let image):
                            ZoomableImageView(image: image)
                        case .failure:
                            AvatarView(
                                url: conversation.participantAvatarUrl,
                                fallback: contactDisplayName,
                                size: 180,
                                cornerRadius: 90
                            )
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    AvatarView(
                        url: conversation.participantAvatarUrl,
                        fallback: contactDisplayName,
                        size: 180,
                        cornerRadius: 90
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showAvatarPreview = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var contactDisplayName: String {
        viewModel.contactDisplayName(for: conversation)
    }

    private var avatarURL: URL? {
        MediaURLResolver.resolve(conversation.participantAvatarUrl)
    }

    private var contactPhoneNumber: String {
        let fallback = String(localized: "Phone number hidden")
        guard let value = viewModel.contactPhoneNumber(for: conversation.participantId),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return fallback
        }
        return value
    }

    private var messages: [Message] {
        viewModel.messages(for: conversation.conversationId)
    }

    private var commonGroups: [CommonGroupPreview] {
        let candidates = viewModel.conversations
            .filter { $0.conversationId != conversation.conversationId }
            .prefix(3)

        return candidates.map { item in
            let groupTitle = "Pingy Circle • \(item.participantUsername)"
            let subtitle = "\(contactDisplayName), \(item.participantUsername)"
            return CommonGroupPreview(
                id: item.conversationId,
                title: groupTitle,
                subtitle: subtitle
            )
        }
    }

    private var mediaCount: Int {
        messages.filter { $0.type == .image || $0.type == .video || $0.type == .voice }.count
    }

    private var documentCount: Int {
        messages.filter { $0.type == .file }.count
    }

    private var linksCount: Int {
        messages.reduce(into: 0) { partial, message in
            let preview = MessageBodyFormatter.previewText(from: message.body, fallback: "")
            let lowered = preview.lowercased()
            if lowered.contains("http://") || lowered.contains("https://") {
                partial += 1
            }
        }
    }

    private var contactShareText: String {
        "\(contactDisplayName)\n\(contactPhoneNumber)"
    }

    private var exportedChatText: String {
        let rows = messages.map { message in
            let dateLabel = formattedExportTime(message.createdAt)
            let sender = message.senderUsername ?? (message.senderId == viewModel.currentUserID ? "Me" : contactDisplayName)
            let fallback = MessageBodyFormatter.fallbackLabel(for: message.type, mediaName: message.mediaName)
            let content = MessageBodyFormatter.previewText(from: message.body, fallback: fallback)
            return "[\(dateLabel)] \(sender): \(content)"
        }

        return rows.joined(separator: "\n")
    }

    private func formattedExportTime(_ raw: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: raw) {
            let output = DateFormatter()
            output.dateStyle = .short
            output.timeStyle = .short
            return output.string(from: date)
        }
        return raw
    }

    private struct CommonGroupPreview {
        let id: String
        let title: String
        let subtitle: String

        var initials: String {
            let comps = title.split(separator: " ")
            let first = comps.first?.first.map(String.init) ?? "G"
            let second = comps.dropFirst().first?.first.map(String.init) ?? ""
            return (first + second).uppercased()
        }
    }
}
