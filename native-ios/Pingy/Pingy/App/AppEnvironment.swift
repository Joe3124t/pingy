import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let configuration = AppConfiguration()
    let themeManager = ThemeManager()
    let sessionStore = SessionStore()
    let apiClient: APIClient
    let authService: AuthService
    let cryptoService = E2EECryptoService()
    let conversationService: ConversationService
    let messageService: MessageService
    let settingsService: SettingsService
    let contactSyncService: ContactSyncService
    let statusService: StatusService
    let socketManager: SocketIOWebSocketManager
    let callSignalingService = CallSignalingService()
    let pushManager: PushNotificationManager
    let authViewModel: AuthViewModel
    let messengerViewModel: MessengerViewModel

    init() {
        apiClient = APIClient(baseURL: configuration.apiBaseURL)
        authService = AuthService(apiClient: apiClient, sessionStore: sessionStore)
        conversationService = ConversationService(apiClient: apiClient, authService: authService)
        messageService = MessageService(apiClient: apiClient, authService: authService)
        settingsService = SettingsService(apiClient: apiClient, authService: authService)
        contactSyncService = ContactSyncService(apiClient: apiClient, authService: authService)
        statusService = StatusService(authService: authService)
        socketManager = SocketIOWebSocketManager(
            webSocketURL: configuration.webSocketURL,
            authService: authService
        )
        pushManager = PushNotificationManager(settingsService: settingsService)
        authViewModel = AuthViewModel(
            authService: authService,
            cryptoService: cryptoService,
            settingsService: settingsService
        )
        messengerViewModel = MessengerViewModel(
            authService: authService,
            conversationService: conversationService,
            messageService: messageService,
            settingsService: settingsService,
            contactSyncService: contactSyncService,
            socketManager: socketManager,
            cryptoService: cryptoService,
            callSignalingService: callSignalingService
        )
    }

    func bootstrap() async {
        await authService.restoreSession()

        if sessionStore.isAuthenticated {
            messengerViewModel.bindSocket()
            await messengerViewModel.reloadAll()
            await pushManager.configure()
        }
    }
}
