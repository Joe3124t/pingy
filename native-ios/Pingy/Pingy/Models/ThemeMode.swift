import Foundation

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case auto

    var id: String { rawValue }
}
