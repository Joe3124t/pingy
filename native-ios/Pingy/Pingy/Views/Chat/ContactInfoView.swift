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
    @State private var showContactDetailsSheet = false
    @State private var showMediaLinksDocsSheet = false
    @State private var showRenameAlert = false
    @State private var renameDraft = ""
    @State private var showSetLockAlert = false
    @State private var showDisableLockAlert = false
    @State private var newLockPasscode = ""
    @State private var confirmLockPasscode = ""
    @State private var disableLockPasscode = ""

    private var muteKey: String {
        "pingy.chat.muted.\(conversation.conversationId)"
    }

    private var saveToPhotosKey: String {
        "pingy.chat.save-to-photos.\(conversation.conversationId)"
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
                    renameDraft = viewModel.localAlias(for: conversation.participantId) ?? contactDisplayName
                    showRenameAlert = true
                }
                .buttonStyle(PingyPressableButtonStyle())
            }
        }
        .onAppear {
            isMuted = UserDefaults.standard.bool(forKey: muteKey)
            saveToPhotos = UserDefaults.standard.bool(forKey: saveToPhotosKey)
            lockChat = ChatLockService.shared.isChatLocked(conversationID: conversation.conversationId)
            isFavorite = UserDefaults.standard.bool(forKey: favoriteKey)
            renameDraft = viewModel.localAlias(for: conversation.participantId) ?? contactDisplayName
        }
        .onChange(of: isMuted) { UserDefaults.standard.set($0, forKey: muteKey) }
        .onChange(of: saveToPhotos) { UserDefaults.standard.set($0, forKey: saveToPhotosKey) }
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
        .alert("Rename contact", isPresented: $showRenameAlert) {
            TextField("Custom name", text: $renameDraft)
            Button("Save") {
                let normalized = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.setLocalAlias(normalized.isEmpty ? nil : normalized, for: conversation.participantId)
                viewModel.showTransientNotice("Contact name updated on this device.", style: .success)
            }
            Button("Reset", role: .destructive) {
                viewModel.setLocalAlias(nil, for: conversation.participantId)
                renameDraft = contactDisplayName
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This name is private to your account on this device.")
        }
        .alert("Set chat password", isPresented: $showSetLockAlert) {
            SecureField("New password", text: $newLockPasscode)
            SecureField("Confirm password", text: $confirmLockPasscode)
            Button("Save") { enableChatLock() }
            Button("Cancel", role: .cancel) {
                newLockPasscode = ""
                confirmLockPasscode = ""
                lockChat = false
            }
        } message: {
            Text("Use at least 4 characters. You will need it every time you open this chat.")
        }
        .alert("Disable chat lock", isPresented: $showDisableLockAlert) {
            SecureField("Current password", text: $disableLockPasscode)
            Button("Disable", role: .destructive) { disableChatLock() }
            Button("Cancel", role: .cancel) {
                disableLockPasscode = ""
                lockChat = true
            }
        } message: {
            Text("Enter the current password to disable lock for this chat.")
        }
        .sheet(isPresented: $showAvatarPreview) {
            avatarPreviewSheet
        }
        .sheet(isPresented: $showContactDetailsSheet) {
            ContactDetailsSheet(
                displayName: contactDisplayName,
                phoneNumber: contactPhoneNumber,
                avatarURL: conversation.participantAvatarUrl,
                onMessageTap: {
                    showContactDetailsSheet = false
                    dismiss()
                },
                onCallTap: {
                    showContactDetailsSheet = false
                    viewModel.startCall(from: conversation)
                }
            )
        }
        .sheet(isPresented: $showMediaLinksDocsSheet) {
            ContactMediaLinksDocsView(
                displayName: contactDisplayName,
                messages: messages
            )
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
                action: {
                    showContactDetailsSheet = true
                }
            )
        }
        .pingyCard()
    }

    private var quickActionsSection: some View {
        HStack(spacing: PingySpacing.sm) {
            quickActionButton(
                icon: "phone.fill",
                title: "Call",
                action: {
                    PingyHaptics.softTap()
                    viewModel.startCall(from: conversation)
                }
            )

            quickActionButton(
                icon: "pencil",
                title: "Rename",
                action: {
                    PingyHaptics.softTap()
                    renameDraft = viewModel.localAlias(for: conversation.participantId) ?? contactDisplayName
                    showRenameAlert = true
                }
            )

            quickActionButton(
                icon: isMuted ? "bell.fill" : "bell.slash.fill",
                title: isMuted ? "Unmute" : "Mute",
                action: {
                    PingyHaptics.softTap()
                    isMuted.toggle()
                }
            )
        }
    }

    private var mediaSection: some View {
        VStack(spacing: 0) {
            sectionRow(
                icon: "photo.on.rectangle.angled",
                title: "Media, links and docs",
                detail: "\(mediaCount + linksCount + documentCount)",
                action: {
                    showMediaLinksDocsSheet = true
                }
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

            toggleRow(icon: "square.and.arrow.down", title: "Save to Photos", isOn: $saveToPhotos)
            Divider().overlay(PingyTheme.border.opacity(0.35))

            sectionRow(
                icon: lockChat ? "lock.fill" : "lock.open",
                title: "Lock chat",
                detail: lockChat ? "On" : "Off",
                tint: PingyTheme.textPrimary,
                action: {
                    handleLockToggle(!lockChat)
                }
            )
        }
        .pingyCard()
    }

    private var actionsSection: some View {
        VStack(spacing: 0) {
            ShareLink(item: contactShareText) {
                sectionLabel(icon: "person.crop.circle.badge.plus", title: "Share contact", tint: PingyTheme.primaryStrong)
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
                    tint: PingyTheme.primaryStrong
                )
            }
            .buttonStyle(PingyPressableButtonStyle())

            Divider().overlay(PingyTheme.border.opacity(0.35))

            ShareLink(item: exportedChatText) {
                sectionLabel(icon: "square.and.arrow.up", title: "Export chat", tint: PingyTheme.primaryStrong)
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
                    .foregroundStyle(PingyTheme.primaryStrong)
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

                Image(systemName: "chevron.forward")
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
        if let value = viewModel.contactPhoneNumber(for: conversation.participantId)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return value
        }

        if let inferred = inferPhoneNumber(from: conversation.participantUsername) {
            return inferred
        }

        if let inferredFromID = inferPhoneNumber(from: conversation.participantId) {
            return inferredFromID
        }

        return String(localized: "Unavailable")
    }

    private var messages: [Message] {
        viewModel.messages(for: conversation.conversationId)
    }

    private var mediaCount: Int {
        messages.filter { $0.type == .image || $0.type == .video || $0.type == .voice }.count
    }

    private var documentCount: Int {
        messages.filter { $0.type == .file }.count
    }

    private var linksCount: Int {
        messages.reduce(into: 0) { partial, message in
            partial += MessageBodyFormatter.extractedLinks(from: message.body).count
        }
    }

    private func inferPhoneNumber(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let allowed = CharacterSet(charactersIn: "+0123456789")
        let filteredScalars = trimmed.unicodeScalars.filter { allowed.contains($0) }
        let candidate = String(String.UnicodeScalarView(filteredScalars))
        let digitsCount = candidate.filter(\.isNumber).count
        return digitsCount >= 8 ? candidate : nil
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

    private func handleLockToggle(_ shouldLock: Bool) {
        PingyHaptics.softTap()
        if shouldLock {
            newLockPasscode = ""
            confirmLockPasscode = ""
            showSetLockAlert = true
            return
        }

        disableLockPasscode = ""
        showDisableLockAlert = true
    }

    private func enableChatLock() {
        do {
            guard !newLockPasscode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !confirmLockPasscode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw ChatLockServiceError.passcodeTooShort
            }
            guard newLockPasscode == confirmLockPasscode else {
                throw ChatLockServiceError.passcodesMismatch
            }

            try ChatLockService.shared.enableLock(
                conversationID: conversation.conversationId,
                passcode: newLockPasscode
            )
            lockChat = true
            newLockPasscode = ""
            confirmLockPasscode = ""
            viewModel.showTransientNotice("Chat lock enabled.", style: .success)
        } catch {
            lockChat = false
            viewModel.showTransientNotice(error.localizedDescription, style: .error)
        }
    }

    private func disableChatLock() {
        do {
            try ChatLockService.shared.disableLock(
                conversationID: conversation.conversationId,
                passcode: disableLockPasscode
            )
            lockChat = false
            disableLockPasscode = ""
            viewModel.showTransientNotice("Chat lock disabled.", style: .success)
        } catch {
            lockChat = true
            viewModel.showTransientNotice(error.localizedDescription, style: .error)
        }
    }
}

private struct ContactDetailsSheet: View {
    let displayName: String
    let phoneNumber: String
    let avatarURL: String?
    let onMessageTap: () -> Void
    let onCallTap: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    Text("Contact details")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(PingyTheme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(PingyTheme.surfaceElevated)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }

                VStack(spacing: 12) {
                    AvatarView(url: avatarURL, fallback: displayName, size: 108, cornerRadius: 54)

                    Text(displayName)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("mobile")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(PingyTheme.textSecondary)

                        Text(phoneNumber)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(PingyTheme.primaryStrong)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PingySpacing.md)
                    .background(PingyTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous)
                            .stroke(PingyTheme.border.opacity(0.35), lineWidth: 1)
                    )
                }

                HStack(spacing: PingySpacing.md) {
                    actionButton(icon: "message.fill", title: "Message", action: onMessageTap)
                    actionButton(icon: "phone.fill", title: "Call", action: onCallTap)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, PingySpacing.md)
            .padding(.top, PingySpacing.sm)
            .padding(.bottom, PingySpacing.lg)
            .background(PingyTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
    }

    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(PingyTheme.primaryStrong)
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(PingyTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PingySpacing.md)
            .background(PingyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PingyRadius.card, style: .continuous)
                    .stroke(PingyTheme.border.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PingyPressableButtonStyle())
    }
}

private struct ContactMediaLinksDocsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case media = "Media"
        case links = "Links"
        case docs = "Docs"

        var id: String { rawValue }
    }

    struct MediaItem: Identifiable {
        let id: String
        let url: URL
        let createdAt: String
    }

    struct LinkItem: Identifiable {
        let id: String
        let url: URL
        let preview: String
        let createdAt: String
    }

    struct DocItem: Identifiable {
        let id: String
        let name: String
        let url: URL
        let createdAt: String
    }

    let displayName: String
    let messages: [Message]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .media
    @State private var selectedMediaURL: URL?

    private var mediaItems: [MediaItem] {
        messages.compactMap { message in
            guard (message.type == .image || message.type == .video),
                  let resolved = MediaURLResolver.resolve(message.mediaUrl)
            else {
                return nil
            }
            return MediaItem(id: message.id, url: resolved, createdAt: message.createdAt)
        }
    }

    private var linkItems: [LinkItem] {
        messages.flatMap { message in
            MessageBodyFormatter.extractedLinks(from: message.body).map { url in
                LinkItem(
                    id: "\(message.id)-\(url.absoluteString)",
                    url: url,
                    preview: MessageBodyFormatter.previewText(from: message.body, fallback: url.absoluteString),
                    createdAt: message.createdAt
                )
            }
        }
    }

    private var docItems: [DocItem] {
        messages.compactMap { message in
            guard message.type == .file,
                  let resolved = MediaURLResolver.resolve(message.mediaUrl)
            else {
                return nil
            }

            let name = message.mediaName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return DocItem(
                id: message.id,
                name: (name?.isEmpty == false ? (name ?? "") : "Document"),
                url: resolved,
                createdAt: message.createdAt
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: PingySpacing.sm) {
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button("Select") {}
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                        .frame(minWidth: 60, alignment: .trailing)
                }
                .padding(.horizontal, PingySpacing.md)
                .padding(.top, PingySpacing.sm)
                .padding(.bottom, PingySpacing.sm)
                .background(PingyTheme.surface)

                content
            }
            .background(PingyTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .buttonStyle(PingyPressableButtonStyle())
                }

                ToolbarItem(placement: .principal) {
                    Text(displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(PingyTheme.textPrimary)
                }
            }
            .sheet(isPresented: selectedMediaPresentedBinding) {
                if let selectedMediaURL {
                    ContactSharedImagePreviewSheet(url: selectedMediaURL)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .media:
            if mediaItems.isEmpty {
                emptyState("No shared media yet.")
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), spacing: 1) {
                        ForEach(mediaItems) { item in
                            Button {
                                selectedMediaURL = item.url
                            } label: {
                                CachedRemoteImage(url: item.url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 94)
                                        .clipped()
                                } placeholder: {
                                    Rectangle()
                                        .fill(PingyTheme.surfaceElevated)
                                        .frame(height: 94)
                                } failure: {
                                    Rectangle()
                                        .fill(PingyTheme.surfaceElevated)
                                        .frame(height: 94)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundStyle(PingyTheme.textSecondary)
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 1)
                }
            }

        case .links:
            if linkItems.isEmpty {
                emptyState("No links shared yet.")
            } else {
                List(linkItems) { item in
                    Link(destination: item.url) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.url.absoluteString)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(PingyTheme.primaryStrong)
                                .lineLimit(2)
                            Text(item.preview)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(PingyTheme.textSecondary)
                                .lineLimit(2)
                            Text(timeLabel(item.createdAt))
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(PingyTheme.textSecondary.opacity(0.8))
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(PingyTheme.surface)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }

        case .docs:
            if docItems.isEmpty {
                emptyState("No documents shared yet.")
            } else {
                List(docItems) { item in
                    Link(destination: item.url) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(PingyTheme.primaryStrong)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(PingyTheme.textPrimary)
                                Text(timeLabel(item.createdAt))
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(PingyTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(PingyTheme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(PingyTheme.surface)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PingyTheme.textSecondary)
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PingyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedMediaPresentedBinding: Binding<Bool> {
        Binding(
            get: { selectedMediaURL != nil },
            set: { isPresented in
                if !isPresented {
                    selectedMediaURL = nil
                }
            }
        )
    }

    private func timeLabel(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let output = DateFormatter()
        output.dateStyle = .medium
        output.timeStyle = .short
        return output.string(from: date)
    }
}

private struct ContactSharedImagePreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let image):
                        ZoomableImageView(image: image)
                    case .failure:
                        Text("Couldn't load image")
                            .foregroundStyle(.white.opacity(0.9))
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
