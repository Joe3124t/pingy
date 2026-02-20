import Foundation

actor ConversationListStateStore {
    static let shared = ConversationListStateStore()

    private let defaults = UserDefaults.standard
    private let pinnedKeyPrefix = "pingy.v3.conversations.pinned."
    private let archivedKeyPrefix = "pingy.v3.conversations.archived."

    func load(for userID: String) -> (pinned: Set<String>, archived: Set<String>) {
        let pinned = Set(defaults.stringArray(forKey: pinnedKeyPrefix + userID) ?? [])
        let archived = Set(defaults.stringArray(forKey: archivedKeyPrefix + userID) ?? [])
        return (pinned, archived)
    }

    func save(pinned: Set<String>, archived: Set<String>, for userID: String) {
        defaults.set(Array(pinned), forKey: pinnedKeyPrefix + userID)
        defaults.set(Array(archived), forKey: archivedKeyPrefix + userID)
    }

    func clear(for userID: String) {
        defaults.removeObject(forKey: pinnedKeyPrefix + userID)
        defaults.removeObject(forKey: archivedKeyPrefix + userID)
    }
}
