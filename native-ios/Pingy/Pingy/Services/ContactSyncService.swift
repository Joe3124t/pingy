import Contacts
import CryptoKit
import Foundation

enum ContactSyncError: LocalizedError {
    case permissionDenied
    case permissionRequired
    case noContacts
    case routeUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied, .permissionRequired:
            return "Enable contact access to find friends."
        case .noContacts:
            return "No contacts found on this device."
        case .routeUnavailable:
            return "Contact sync route is not available on this backend yet."
        }
    }
}

final class ContactSyncService {
    private let authService: AuthorizedRequester
    private let contactStore = CNContactStore()
    private var cachedHashEntries: [ContactHashEntry] = []
    private var cachedLocalEntries: [LocalContactEntry] = []

    private struct LocalContactEntry {
        let label: String
        let phoneNumbers: [String]
    }

    init(apiClient _: APIClient, authService: AuthorizedRequester) {
        self.authService = authService
    }

    func syncContacts(promptForPermission: Bool) async throws -> [ContactSearchResult] {
        let hasAccess = await resolveContactsAccess(promptForPermission: promptForPermission)
        guard hasAccess else {
            throw promptForPermission ? ContactSyncError.permissionDenied : ContactSyncError.permissionRequired
        }

        let (hashedContacts, _) = try loadContactIndex()
        guard !hashedContacts.isEmpty else {
            throw ContactSyncError.noContacts
        }

        var allMatches: [ContactSyncMatch] = []
        let chunkSize = 5000
        var start = 0

        while start < hashedContacts.count {
            let end = min(start + chunkSize, hashedContacts.count)
            let chunk = Array(hashedContacts[start ..< end])
            start = end

            let endpoint = try Endpoint.json(
                path: "users/contact-sync",
                method: .post,
                payload: ContactSyncRequest(contacts: chunk)
            )

            do {
                let response: ContactSyncResponse = try await authService.authorizedRequest(endpoint, as: ContactSyncResponse.self)
                allMatches.append(contentsOf: response.matches)
            } catch let apiError as APIError {
                if case .server(let statusCode, let message) = apiError {
                    let lowered = message.lowercased()
                    if statusCode == 404 || lowered.contains("route not found") {
                        throw ContactSyncError.routeUnavailable
                    }
                }
                throw apiError
            }
        }

        let localLabelByHash = Dictionary(uniqueKeysWithValues: hashedContacts.map { ($0.hash, $0.label) })
        var byUserID: [String: ContactSearchResult] = [:]

        allMatches.forEach { match in
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

    func searchRegisteredUsersByContactName(query: String, limit: Int = 15) async throws -> [ContactSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        let hasAccess = await resolveContactsAccess(promptForPermission: false)
        guard hasAccess else {
            throw ContactSyncError.permissionRequired
        }

        let (_, localEntries) = try loadContactIndex()
        let candidates = localEntries.filter { $0.label.lowercased().contains(normalizedQuery) }
        guard !candidates.isEmpty else { return [] }

        var userById: [String: ContactSearchResult] = [:]

        for entry in candidates.prefix(30) {
            for phone in entry.phoneNumbers.prefix(3) {
                let foundUsers = try await searchUsersByPhone(phone, limit: 3)
                for user in foundUsers {
                    userById[user.id] = ContactSearchResult(
                        id: user.id,
                        user: user,
                        contactName: entry.label
                    )
                }
                if userById.count >= limit {
                    break
                }
            }
            if userById.count >= limit {
                break
            }
        }

        return Array(userById.values)
            .sorted { lhs, rhs in
                lhs.contactName.localizedCaseInsensitiveCompare(rhs.contactName) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
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

    private func loadContactIndex() throws -> ([ContactHashEntry], [LocalContactEntry]) {
        if !cachedHashEntries.isEmpty || !cachedLocalEntries.isEmpty {
            return (cachedHashEntries, cachedLocalEntries)
        }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        request.unifyResults = true

        var hashToLabel: [String: String] = [:]
        var localEntries: [LocalContactEntry] = []

        try contactStore.enumerateContacts(with: request) { contact, _ in
            let displayName = Self.displayName(for: contact)
            guard !displayName.isEmpty else { return }

            var normalizedNumbersForContact: Set<String> = []
            contact.phoneNumbers.forEach { number in
                let raw = number.value.stringValue
                Self.normalizedPhoneCandidates(from: raw).forEach { normalized in
                    normalizedNumbersForContact.insert(normalized)
                    let hash = Self.sha256Hex(normalized)
                    if hashToLabel[hash] == nil {
                        hashToLabel[hash] = displayName
                    }
                }
            }

            if !normalizedNumbersForContact.isEmpty {
                localEntries.append(
                    LocalContactEntry(
                        label: displayName,
                        phoneNumbers: Array(normalizedNumbersForContact)
                    )
                )
            }
        }

        let hashEntries = hashToLabel.map { ContactHashEntry(hash: $0.key, label: $0.value) }
        cachedHashEntries = hashEntries
        cachedLocalEntries = localEntries
        return (hashEntries, localEntries)
    }

    private func searchUsersByPhone(_ phoneNumber: String, limit: Int) async throws -> [User] {
        struct SearchUsersResponse: Decodable {
            let users: [User]
        }

        let endpoint = Endpoint(
            path: "users",
            method: .get,
            queryItems: [
                URLQueryItem(name: "query", value: phoneNumber),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )

        let response: SearchUsersResponse = try await authService.authorizedRequest(endpoint, as: SearchUsersResponse.self)
        return response.users
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
