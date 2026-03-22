import Foundation
import OSLog

// MARK: - Keychain Protocol

protocol SecureStorage: Sendable {
    func save(_ value: String, forKey key: String) throws
    func load(forKey key: String) throws -> String
    func delete(forKey key: String) throws
}

// MARK: - KeychainError (kept for API compatibility)

enum KeychainError: LocalizedError {
    case itemNotFound
    case unexpectedData
    case unhandledError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:          return "Item not found."
        case .unexpectedData:        return "Unexpected data format."
        case .unhandledError(let s): return "Storage error (OSStatus \(s))."
        }
    }
}

// MARK: - KeychainManager
//
// Stores Jira credentials using SecureStorageService:
// master key lives in Keychain (one-time prompt), credentials are AES-256-GCM encrypted in UserDefaults.

final class KeychainManager: SecureStorage, @unchecked Sendable {

    static let shared = KeychainManager()

    private let storage = SecureStorageService.shared
    private let logger = Logger(subsystem: "com.standapp", category: "Keychain")

    private init() {}

    // MARK: - SecureStorage

    func save(_ value: String, forKey key: String) throws {
        do {
            try storage.save(value, forKey: key)
            logger.debug("Keychain: saved key '\(key)'")
        } catch {
            throw KeychainError.unhandledError(status: -1)
        }
    }

    func load(forKey key: String) throws -> String {
        do {
            return try storage.load(forKey: key)
        } catch SecureStorageError.itemNotFound {
            throw KeychainError.itemNotFound
        } catch {
            throw KeychainError.unhandledError(status: -1)
        }
    }

    func delete(forKey key: String) throws {
        storage.delete(forKey: key)
        logger.debug("Keychain: deleted key '\(key)'")
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
        storage.contains(key: Keys.subdomain) &&
        storage.contains(key: Keys.email) &&
        storage.contains(key: Keys.apiToken)
    }
}
