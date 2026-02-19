import Foundation
import SwiftUI

@MainActor
final class ThemeManager: ObservableObject {
    private enum StorageKeys {
        static let appearanceMode = "pingy.appearance.mode"
    }

    @Published var appearanceMode: ThemeMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: StorageKeys.appearanceMode)
        }
    }

    var preferredColorScheme: ColorScheme? {
        appearanceMode.colorSchemeOverride
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let storedMode = defaults.string(forKey: StorageKeys.appearanceMode),
           let decoded = ThemeMode(rawValue: storedMode)
        {
            appearanceMode = decoded
        } else {
            appearanceMode = .auto
        }
    }
}
