import Foundation
import Security
import OSLog

// MARK: - Keychain Protocol

protocol SecureStorage: Sendable {
    func save(_ value: String, forKey key: String) throws
    func load(forKey key: String) throws -> String
    func delete(forKey key: String) throws
}

// MARK: - Keychain Error

enum KeychainError: LocalizedError {
    case itemNotFound
    case unexpectedData
    case unhandledError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:         return "Keychain item not found."
        case .unexpectedData:       return "Keychain returned unexpected data format."
        case .unhandledError(let s): return "Keychain error (OSStatus \(s))."
        }
    }
}

// MARK: - KeychainManager

final class KeychainManager: SecureStorage, @unchecked Sendable {

    static let shared = KeychainManager()

    private let service: String
    private let logger = Logger(subsystem: "com.standapp", category: "Keychain")

    private init(service: String = "com.standapp.jira") {
        self.service = service
    }

    // MARK: - SecureStorage

    func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.unexpectedData }

        // Attempt update first; if not found, add new item.
        let query = baseQuery(forKey: key)
        let attributes: [CFString: Any] = [kSecValueData: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("Keychain add failed for key '\(key)': \(addStatus)")
                throw KeychainError.unhandledError(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            logger.error("Keychain update failed for key '\(key)': \(updateStatus)")
            throw KeychainError.unhandledError(status: updateStatus)
        }

        logger.debug("Keychain item saved for key '\(key)'")
    }

    func load(forKey key: String) throws -> String {
        var query = baseQuery(forKey: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return value
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            logger.error("Keychain load failed for key '\(key)': \(status)")
            throw KeychainError.unhandledError(status: status)
        }
    }

    func delete(forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed for key '\(key)': \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        logger.debug("Keychain item deleted for key '\(key)'")
    }

    // MARK: - Helpers

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

// MARK: - Typed Jira Credential Keys

extension KeychainManager {

    private enum Keys {
        static let subdomain = "jira.subdomain"
        static let email     = "jira.email"
        static let apiToken  = "jira.apiToken"
    }

    func saveJiraCredentials(_ credentials: JiraCredentials) throws {
        try save(credentials.subdomain, forKey: Keys.subdomain)
        try save(credentials.email,     forKey: Keys.email)
        try save(credentials.apiToken,  forKey: Keys.apiToken)
    }

    func loadJiraCredentials() throws -> JiraCredentials {
        let subdomain = try load(forKey: Keys.subdomain)
        let email     = try load(forKey: Keys.email)
        let apiToken  = try load(forKey: Keys.apiToken)
        return JiraCredentials(subdomain: subdomain, email: email, apiToken: apiToken)
    }

    func deleteJiraCredentials() {
        try? delete(forKey: Keys.subdomain)
        try? delete(forKey: Keys.email)
        try? delete(forKey: Keys.apiToken)
    }

    /// Returns true only if all three credential keys are present.
    var hasJiraCredentials: Bool {
        (try? loadJiraCredentials()) != nil
    }
}
