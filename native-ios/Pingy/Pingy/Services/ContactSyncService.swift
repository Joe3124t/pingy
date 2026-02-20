import Contacts
import CryptoKit
import Foundation

enum ContactSyncError: LocalizedError {
    case permissionDenied
    case permissionRequired
    case noContacts

    var errorDescription: String? {
        switch self {
        case .permissionDenied, .permissionRequired:
            return "Enable contact access to find friends."
        case .noContacts:
            return "No contacts found on this device."
        }
    }
}

final class ContactSyncService {
    private let authService: AuthorizedRequester
    private let contactStore = CNContactStore()

    init(apiClient _: APIClient, authService: AuthorizedRequester) {
        self.authService = authService
    }

    func syncContacts(promptForPermission: Bool) async throws -> [ContactSearchResult] {
        let hasAccess = await resolveContactsAccess(promptForPermission: promptForPermission)
        guard hasAccess else {
            throw promptForPermission ? ContactSyncError.permissionDenied : ContactSyncError.permissionRequired
        }

        let hashedContacts = try loadHashedContacts()
        guard !hashedContacts.isEmpty else {
            throw ContactSyncError.noContacts
        }

        let endpoint = try Endpoint.json(
            path: "users/contact-sync",
            method: .post,
            payload: ContactSyncRequest(contacts: hashedContacts)
        )

        let response: ContactSyncResponse = try await authService.authorizedRequest(endpoint, as: ContactSyncResponse.self)

        let localLabelByHash = Dictionary(uniqueKeysWithValues: hashedContacts.map { ($0.hash, $0.label) })
        var byUserID: [String: ContactSearchResult] = [:]

        response.matches.forEach { match in
            let contactName = (match.contactName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? match.contactName
                : localLabelByHash[match.hash]) ?? match.user.username

            byUserID[match.user.id] = ContactSearchResult(
                id: match.user.id,
                user: match.user,
                contactName: contactName
            )
        }

        return byUserID.values.sorted {
            $0.contactName.localizedCaseInsensitiveCompare($1.contactName) == .orderedAscending
        }
    }

    private func resolveContactsAccess(promptForPermission: Bool) async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return true
        case .notDetermined:
            guard promptForPermission else { return false }
            return await withCheckedContinuation { continuation in
                contactStore.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func loadHashedContacts() throws -> [ContactHashEntry] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        request.unifyResults = true

        var hashToLabel: [String: String] = [:]

        try contactStore.enumerateContacts(with: request) { contact, _ in
            let displayName = Self.displayName(for: contact)
            guard !displayName.isEmpty else { return }

            contact.phoneNumbers.forEach { number in
                let raw = number.value.stringValue
                Self.normalizedPhoneCandidates(from: raw).forEach { normalized in
                    let hash = Self.sha256Hex(normalized)
                    if hashToLabel[hash] == nil {
                        hashToLabel[hash] = displayName
                    }
                }
            }
        }

        return hashToLabel.map { ContactHashEntry(hash: $0.key, label: $0.value) }
    }

    private static func displayName(for contact: CNContact) -> String {
        let value = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            return value
        }
        return "Unknown"
    }

    private static func normalizedPhoneCandidates(from raw: String) -> Set<String> {
        var result = Set<String>()
        let compact = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)

        guard !compact.isEmpty else { return result }

        if compact.hasPrefix("+") {
            let digits = compact.dropFirst().filter(\.isNumber)
            if (8 ... 15).contains(digits.count) {
                result.insert("+\(digits)")
            }
            return result
        }

        let digitsOnly = compact.filter(\.isNumber)
        guard !digitsOnly.isEmpty else { return result }

        if (8 ... 15).contains(digitsOnly.count) {
            result.insert("+\(digitsOnly)")
        }

        // Egypt-friendly fallback for local mobile format, e.g. 01XXXXXXXXX -> +201XXXXXXXXX
        if digitsOnly.hasPrefix("0"), digitsOnly.count >= 10 {
            let dropped = String(digitsOnly.dropFirst())
            if (8 ... 15).contains(dropped.count + 2) {
                result.insert("+20\(dropped)")
            }
        }

        return result
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
