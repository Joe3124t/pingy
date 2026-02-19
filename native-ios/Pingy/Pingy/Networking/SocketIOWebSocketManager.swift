import Foundation

enum SocketError: LocalizedError {
    case notConnected
    case ackTimeout
    case invalidAckPayload

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Socket is not connected"
        case .ackTimeout:
            return "Socket acknowledgement timeout"
        case .invalidAckPayload:
            return "Invalid socket acknowledgement payload"
        }
    }
}

enum SocketEvent {
    case messageNew(Message)
    case messageDelivered(MessageLifecycleUpdate)
    case messageSeen(MessageLifecycleUpdate)
    case messageReaction(ReactionUpdate)
    case typingStart(TypingEvent)
    case typingStop(TypingEvent)
    case presenceSnapshot(PresenceSnapshot)
    case presenceUpdate(PresenceUpdate)
    case profileUpdate(ProfileUpdateEvent)
    case conversationWallpaper(ConversationWallpaperEvent)
}

@MainActor
final class SocketIOWebSocketManager: ObservableObject {
    @Published private(set) var isConnected = false

    var onEvent: ((SocketEvent) -> Void)?

    private let webSocketURL: URL
    private let authService: AuthService
    private let urlSession = URLSession(configuration: .default)
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var shouldReconnect = true
    private var isConnecting = false
    private var reconnectAttempts = 0
    private var nextAckID = 1
    private var ackHandlers: [Int: (Result<JSONValue, Error>) -> Void] = [:]

    init(webSocketURL: URL, authService: AuthService) {
        self.webSocketURL = webSocketURL
        self.authService = authService
    }

    func connectIfNeeded() {
        guard webSocketTask == nil, !isConnecting, !isConnected else { return }
        shouldReconnect = true
        Task {
            await connect()
        }
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnecting = false
        isConnected = false
    }

    func joinConversation(_ conversationId: String) {
        struct JoinPayload: Encodable { let conversationId: String }
        Task {
            _ = try? await emitWithAck(event: "conversation:join", payload: JoinPayload(conversationId: conversationId))
        }
    }

    func leaveConversation(_ conversationId: String) {
        struct LeavePayload: Encodable { let conversationId: String }
        Task {
            try? await emit(event: "conversation:leave", payload: LeavePayload(conversationId: conversationId))
        }
    }

    func sendTypingStart(conversationId: String) {
        struct TypingPayload: Encodable { let conversationId: String }
        Task {
            try? await emit(event: "typing:start", payload: TypingPayload(conversationId: conversationId))
        }
    }

    func sendTypingStop(conversationId: String) {
        struct TypingPayload: Encodable { let conversationId: String }
        Task {
            try? await emit(event: "typing:stop", payload: TypingPayload(conversationId: conversationId))
        }
    }

    func sendSeen(conversationId: String, messageIds: [String] = []) {
        struct SeenPayload: Encodable {
            let conversationId: String
            let messageIds: [String]
        }
        Task {
            _ = try? await emitWithAck(
                event: "message:seen",
                payload: SeenPayload(conversationId: conversationId, messageIds: messageIds)
            )
        }
    }

    func sendEncryptedMessage(
        conversationId: String,
        body: EncryptedPayload,
        clientId: String,
        replyToMessageId: String?
    ) async throws -> Message {
        struct SendPayload: Encodable {
            let conversationId: String
            let body: EncryptedPayload
            let isEncrypted: Bool
            let clientId: String
            let replyToMessageId: String?
        }

        let ack = try await emitWithAck(
            event: "message:send",
            payload: SendPayload(
                conversationId: conversationId,
                body: body,
                isEncrypted: true,
                clientId: clientId,
                replyToMessageId: replyToMessageId
            )
        )

        guard let payloadObject = ack.objectValue else {
            throw SocketError.invalidAckPayload
        }
        guard (payloadObject["ok"]?.boolValue ?? false) == true else {
            let message = payloadObject["message"]?.stringValue ?? "Message send failed"
            throw APIError.server(statusCode: 400, message: message)
        }

        guard let messageValue = payloadObject["message"] else {
            throw SocketError.invalidAckPayload
        }
        let messageData = try JSONEncoder().encode(messageValue)
        return try decoder.decode(Message.self, from: messageData)
    }

    private func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

        do {
            let token = try await authService.validAccessToken()
            var request = URLRequest(url: webSocketURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20

            let task = urlSession.webSocketTask(with: request)
            webSocketTask = task
            AppLogger.debug("Socket connecting...")
            task.resume()
            startReceiveLoop(task: task)
        } catch {
            AppLogger.error("Socket connect failed: \(error.localizedDescription)")
            scheduleReconnect()
        }
    }

    private func startReceiveLoop(task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let frame):
                        await self.handleSocketFrame(frame)
                    case .data(let data):
                        if let frame = String(data: data, encoding: .utf8) {
                            await self.handleSocketFrame(frame)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    await self.handleDisconnect(error: error)
                    return
                }
            }
        }
    }

    private func handleDisconnect(error: Error) {
        AppLogger.error("Socket disconnected: \(error.localizedDescription)")
        isConnected = false
        webSocketTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldReconnect, authService.sessionStore.isAuthenticated else { return }
        reconnectTask?.cancel()
        reconnectAttempts += 1

        let delaySeconds = min(Double(reconnectAttempts * 2), 12.0)
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.connect()
        }
    }

    private func handleSocketFrame(_ frame: String) async {
        if frame == "2" {
            try? await sendRaw("3")
            return
        }

        if frame.hasPrefix("0") {
            reconnectAttempts = 0
            try? await sendRaw("40")
            return
        }

        if frame == "40" {
            isConnected = true
            reconnectAttempts = 0
            AppLogger.debug("Socket connected.")
            return
        }

        if frame.hasPrefix("42") {
            handleEventPacket(frame)
            return
        }

        if frame.hasPrefix("43") {
            handleAckPacket(frame)
        }
    }

    private func handleEventPacket(_ packet: String) {
        guard let bracketIndex = packet.firstIndex(of: "[") else { return }
        let json = String(packet[bracketIndex...])
        guard let data = json.data(using: .utf8) else { return }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any], array.count >= 1 else {
            return
        }

        guard let eventName = array.first as? String else { return }
        let payload = array.count > 1 ? array[1] : [:]

        do {
            switch eventName {
            case "message:new":
                let value: Message = try decodePayload(payload, as: Message.self)
                onEvent?(.messageNew(value))
            case "message:delivered":
                let value: MessageLifecycleUpdate = try decodePayload(payload, as: MessageLifecycleUpdate.self)
                onEvent?(.messageDelivered(value))
            case "message:seen":
                let value: MessageLifecycleUpdate = try decodePayload(payload, as: MessageLifecycleUpdate.self)
                onEvent?(.messageSeen(value))
            case "message:reaction":
                let value: ReactionUpdate = try decodePayload(payload, as: ReactionUpdate.self)
                onEvent?(.messageReaction(value))
            case "typing:start":
                let value: TypingEvent = try decodePayload(payload, as: TypingEvent.self)
                onEvent?(.typingStart(value))
            case "typing:stop":
                let value: TypingEvent = try decodePayload(payload, as: TypingEvent.self)
                onEvent?(.typingStop(value))
            case "presence:snapshot":
                let value: PresenceSnapshot = try decodePayload(payload, as: PresenceSnapshot.self)
                onEvent?(.presenceSnapshot(value))
            case "presence:update":
                let value: PresenceUpdate = try decodePayload(payload, as: PresenceUpdate.self)
                onEvent?(.presenceUpdate(value))
            case "profile:update":
                let value: ProfileUpdateEvent = try decodePayload(payload, as: ProfileUpdateEvent.self)
                onEvent?(.profileUpdate(value))
            case "conversation:wallpaper":
                let value: ConversationWallpaperEvent = try decodePayload(payload, as: ConversationWallpaperEvent.self)
                onEvent?(.conversationWallpaper(value))
            default:
                break
            }
        } catch {
            AppLogger.error("Socket event decode failed: \(eventName) - \(error.localizedDescription)")
        }
    }

    private func handleAckPacket(_ packet: String) {
        guard let bracketIndex = packet.firstIndex(of: "[") else { return }
        let idPart = packet.dropFirst(2).prefix { $0 != "[" }
        guard let ackID = Int(idPart) else { return }
        guard let data = String(packet[bracketIndex...]).data(using: .utf8) else { return }
        guard let json = try? JSONDecoder().decode([JSONValue].self, from: data) else { return }

        let value = json.first ?? .null
        let handler = ackHandlers.removeValue(forKey: ackID)
        handler?(.success(value))
    }

    private func decodePayload<T: Decodable>(_ payload: Any, as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try decoder.decode(T.self, from: data)
    }

    private func sendRaw(_ value: String) async throws {
        guard let task = webSocketTask else {
            throw SocketError.notConnected
        }
        try await task.send(.string(value))
    }

    func emit<T: Encodable>(event: String, payload: T) async throws {
        let frame = try makeEmitPacket(event: event, payload: payload, ackID: nil)
        try await sendRaw(frame)
    }

    func emitWithAck<T: Encodable>(event: String, payload: T) async throws -> JSONValue {
        guard isConnected, webSocketTask != nil else {
            throw SocketError.notConnected
        }

        let ackID = nextAckID
        nextAckID += 1
        let frame = try makeEmitPacket(event: event, payload: payload, ackID: ackID)

        return try await withCheckedThrowingContinuation { continuation in
            ackHandlers[ackID] = { result in
                continuation.resume(with: result)
            }

            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.sendRaw(frame)
                    try await Task.sleep(nanoseconds: 8_000_000_000)
                    if let handler = self.ackHandlers.removeValue(forKey: ackID) {
                        handler(.failure(SocketError.ackTimeout))
                    }
                } catch {
                    if let handler = self.ackHandlers.removeValue(forKey: ackID) {
                        handler(.failure(error))
                    }
                }
            }
        }
    }

    private func makeEmitPacket<T: Encodable>(
        event: String,
        payload: T,
        ackID: Int?
    ) throws -> String {
        let payloadData = try encoder.encode(payload)
        let payloadObject = try JSONSerialization.jsonObject(with: payloadData)
        let array: [Any] = [event, payloadObject]
        let data = try JSONSerialization.data(withJSONObject: array)
        guard let payloadJSON = String(data: data, encoding: .utf8) else {
            throw APIError.decodingError
        }

        if let ackID {
            return "42\(ackID)\(payloadJSON)"
        }
        return "42\(payloadJSON)"
    }
}

private extension JSONValue {
    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }
}
