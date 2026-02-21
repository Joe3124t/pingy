import SwiftUI
import UIKit

struct ChatMediaGalleryEntry: Identifiable {
    let id: String
    let message: Message
    let url: URL
}

struct ChatMediaViewerState: Identifiable {
    let id = UUID()
    let entries: [ChatMediaGalleryEntry]
    let initialIndex: Int
}

private struct ChatMediaInfo {
    let fileSizeBytes: Int
    let width: Int
    let height: Int
    let source: String
}

struct ChatMediaViewer: View {
    let entries: [ChatMediaGalleryEntry]
    let initialIndex: Int
    let currentUserID: String?
    let onDismiss: () -> Void
    let onReply: (Message) -> Void
    let onDeleteOwnMessage: (Message) -> Void

    @State private var selection: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isInfoPresented = false
    @State private var isSharePresented = false
    @State private var shareURL: URL?
    @State private var mediaInfo: ChatMediaInfo?
    @State private var showSaveToast = false
    @State private var reloadToken = UUID()

    init(
        entries: [ChatMediaGalleryEntry],
        initialIndex: Int,
        currentUserID: String?,
        onDismiss: @escaping () -> Void,
        onReply: @escaping (Message) -> Void,
        onDeleteOwnMessage: @escaping (Message) -> Void
    ) {
        self.entries = entries
        self.initialIndex = initialIndex
        self.currentUserID = currentUserID
        self.onDismiss = onDismiss
        self.onReply = onReply
        self.onDeleteOwnMessage = onDeleteOwnMessage
        _selection = State(initialValue: min(max(0, initialIndex), max(0, entries.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    CachedRemoteImage(url: entry.url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(ProgressView().tint(.white))
                            .padding(30)
                    } failure: {
                        Button {
                            reloadToken = UUID()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.92))
                                Text("Tap to retry")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                    .id(reloadToken)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            onDismiss()
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                dragOffset = 0
                            }
                        }
                    }
            )

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }

            if showSaveToast {
                VStack {
                    Spacer()
                    Text("Saved to Photos")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.72))
                        .clipShape(Capsule())
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            Task { await refreshMediaInfo() }
            preloadNearbyImages()
        }
        .onChange(of: selection) { _ in
            Task { await refreshMediaInfo() }
            preloadNearbyImages()
        }
        .sheet(isPresented: $isInfoPresented) {
            ChatMediaInfoView(
                entry: currentEntry,
                info: mediaInfo
            )
        }
        .sheet(isPresented: $isSharePresented) {
            if let shareURL {
                ActivityView(activityItems: [shareURL])
            }
        }
    }

    private var currentEntry: ChatMediaGalleryEntry {
        entries[min(max(0, selection), max(0, entries.count - 1))]
    }

    private var currentMessage: Message {
        currentEntry.message
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(PingyPressableButtonStyle())

            VStack(alignment: .leading, spacing: 2) {
                Text((currentMessage.senderUsername?.isEmpty == false) ? (currentMessage.senderUsername ?? "Pingy") : "Pingy")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(formattedTime(currentMessage.createdAt))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }

            Spacer()

            Menu {
                Button("Info", systemImage: "info.circle") {
                    isInfoPresented = true
                }
                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                    saveCurrentImageToPhotos()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(PingyPressableButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.28).blur(radius: 8))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            actionButton("Reply", icon: "arrowshape.turn.up.left.fill") {
                onReply(currentMessage)
            }

            actionButton("Forward", icon: "arrowshape.turn.up.right.fill") {}

            actionButton("Share", icon: "square.and.arrow.up") {
                shareURL = currentEntry.url
                isSharePresented = true
            }

            actionButton("Save", icon: "square.and.arrow.down") {
                saveCurrentImageToPhotos()
            }

            if currentMessage.senderId == currentUserID {
                actionButton("Delete", icon: "trash.fill") {
                    onDeleteOwnMessage(currentMessage)
                }
            }

            actionButton("Info", icon: "info.circle.fill") {
                isInfoPresented = true
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(PingyPressableButtonStyle())
    }

    private func formattedTime(_ iso: String?) -> String {
        guard let iso else { return "Now" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "Now" }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    private func preloadNearbyImages() {
        let previousIndex = selection - 1
        let nextIndex = selection + 1

        Task(priority: .background) {
            if previousIndex >= 0, previousIndex < entries.count {
                _ = await RemoteImageStore.shared.fetchImage(for: entries[previousIndex].url)
            }
            if nextIndex >= 0, nextIndex < entries.count {
                _ = await RemoteImageStore.shared.fetchImage(for: entries[nextIndex].url)
            }
        }
    }

    private func refreshMediaInfo() async {
        if currentEntry.url.isFileURL {
            guard let data = try? Data(contentsOf: currentEntry.url),
                  let image = UIImage(data: data)
            else {
                await MainActor.run {
                    mediaInfo = nil
                }
                return
            }

            let info = ChatMediaInfo(
                fileSizeBytes: data.count,
                width: Int(image.size.width * image.scale),
                height: Int(image.size.height * image.scale),
                source: inferSource()
            )
            await MainActor.run {
                mediaInfo = info
            }
            return
        }

        let image = await RemoteImageStore.shared.fetchImage(for: currentEntry.url)
        let fileSize = await estimateRemoteFileSize(url: currentEntry.url)
        let info = ChatMediaInfo(
            fileSizeBytes: fileSize,
            width: Int((image?.size.width ?? 0) * (image?.scale ?? 1)),
            height: Int((image?.size.height ?? 0) * (image?.scale ?? 1)),
            source: inferSource()
        )
        await MainActor.run {
            mediaInfo = info
        }
    }

    private func estimateRemoteFileSize(url: URL) async -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               let value = http.value(forHTTPHeaderField: "Content-Length"),
               let size = Int(value)
            {
                return size
            }
        } catch {}
        return 0
    }

    private func inferSource() -> String {
        let name = (currentMessage.mediaName ?? "").lowercased()
        if name.contains("camera") {
            return "camera"
        }
        return "gallery"
    }

    private func saveCurrentImageToPhotos() {
        Task {
            let image = await RemoteImageStore.shared.fetchImage(for: currentEntry.url)
            guard let image else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            await MainActor.run {
                PingyHaptics.success()
                withAnimation(.easeOut(duration: 0.2)) {
                    showSaveToast = true
                }
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    showSaveToast = false
                }
            }
        }
    }
}

private struct ChatMediaInfoView: View {
    let entry: ChatMediaGalleryEntry
    let info: ChatMediaInfo?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Media") {
                    infoRow("Sender", value: (entry.message.senderUsername?.isEmpty == false) ? (entry.message.senderUsername ?? "Unknown") : "Unknown")
                    infoRow("Sent time", value: formatDate(entry.message.createdAt))
                    infoRow("Delivered", value: formatDate(entry.message.deliveredAt))
                    infoRow("Read", value: formatDate(entry.message.seenAt))
                    infoRow("File size", value: formatBytes(info?.fileSizeBytes ?? 0))
                    infoRow("Resolution", value: "\(info?.width ?? 0)x\(info?.height ?? 0)")
                    infoRow("Upload source", value: info?.source.capitalized ?? "Unknown")
                }
            }
            .navigationTitle("Media info")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDate(_ iso: String?) -> String {
        guard let iso else { return "-" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "-" }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    private func formatBytes(_ bytes: Int) -> String {
        guard bytes > 0 else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

