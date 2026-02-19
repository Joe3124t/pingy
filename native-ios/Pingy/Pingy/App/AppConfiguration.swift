import Foundation

struct AppConfiguration {
    let apiBaseURL: URL
    let webSocketURL: URL

    init(bundle: Bundle = .main) {
        let apiFallback = "https://pingy-backend-production.up.railway.app/api"
        let wsFallback = "wss://pingy-backend-production.up.railway.app/socket.io/?EIO=4&transport=websocket"

        let apiString = (bundle.object(forInfoDictionaryKey: "PINGY_API_BASE_URL") as? String) ?? apiFallback
        let wsString = (bundle.object(forInfoDictionaryKey: "PINGY_WS_BASE_URL") as? String) ?? wsFallback

        guard let resolvedAPI = URL(string: apiString) else {
            fatalError("Invalid PINGY_API_BASE_URL in Info.plist")
        }

        guard let resolvedWS = URL(string: wsString) else {
            fatalError("Invalid PINGY_WS_BASE_URL in Info.plist")
        }

        apiBaseURL = resolvedAPI
        webSocketURL = resolvedWS
    }
}
