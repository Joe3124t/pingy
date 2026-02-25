import CryptoKit
import Foundation

enum ChatLockServiceError: LocalizedError {
    case passcodeTooShort
    case passcodesMismatch
    case passcodeNotConfigured
    case invalidPasscode

    var errorDescription: String? {
        switch self {
        case .passcodeTooShort:
            return "Password must be at least 4 characters."
        case .passcodesMismatch:
            return "Passwords do not match."
        case .passcodeNotConfigured:
            return "No password is set for this chat yet."
        case .invalidPasscode:
            return "Incorrect chat password."
        }
    }
}

final class ChatLockService {
    static let shared = ChatLockService()

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore.shared

    private init() {}

    func isChatLocked(conversationID: String) -> Bool {
        defaults.bool(forKey: enabledKey(for: conversationID))
    }

    func enableLock(conversationID: String, passcode: String) throws {
        let normalized = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 4 else {
            throw ChatLockServiceError.passcodeTooShort
        }

        try keychain.set(hash(passcode: normalized), for: passcodeKey(for: conversationID))
        defaults.set(true, forKey: enabledKey(for: conversationID))
    }

    func disableLock(conversationID: String, passcode: String) throws {
        guard isChatLocked(conversationID: conversationID) else { return }
        guard verify(passcode: passcode, for: conversationID) else {
            throw ChatLockServiceError.invalidPasscode
        }

        try keychain.delete(passcodeKey(for: conversationID))
        defaults.set(false, forKey: enabledKey(for: conversationID))
    }

    func verify(passcode: String, for conversationID: String) -> Bool {
        let normalized = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        guard let storedHash = try? keychain.string(for: passcodeKey(for: conversationID)),
              let storedHash,
              !storedHash.isEmpty
        else {
            return false
        }

        return storedHash == hash(passcode: normalized)
    }

    func hasPasscode(conversationID: String) -> Bool {
        guard let value = try? keychain.string(for: passcodeKey(for: conversationID)) else {
            return false
        }
        return !(value ?? "").isEmpty
    }

    private func enabledKey(for conversationID: String) -> String {
        "pingy.chat.lock.enabled.\(conversationID)"
    }

    private func passcodeKey(for conversationID: String) -> String {
        "pingy.chat.lock.passcode.\(conversationID)"
    }

    private func hash(passcode: String) -> String {
        let digest = SHA256.hash(data: Data(passcode.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
