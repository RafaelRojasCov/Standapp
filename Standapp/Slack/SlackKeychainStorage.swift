import Foundation
import OSLog

// MARK: - KeychainStorage Protocol (I-SPEC)

protocol KeychainStorage: Sendable {
    func save(token: String) throws
    func retrieve() throws -> String?
    func delete() throws
}

// MARK: - Slack Secure Storage
//
// Stores the Slack Bot Token using SecureStorageService:
// master key lives in Keychain (one-time prompt), token is AES-256-GCM encrypted in UserDefaults.

final class SlackKeychainStorage: KeychainStorage, @unchecked Sendable {

    static let shared = SlackKeychainStorage()

    private let storage = SecureStorageService.shared
    private let tokenKey = "slack.botToken"
    private let logger = Logger(subsystem: "com.standapp", category: "SlackStorage")

    private init() {}

    // MARK: - KeychainStorage

    func save(token: String) throws {
        try storage.save(token, forKey: tokenKey)
        logger.debug("Slack Bot Token saved")
    }

    func retrieve() throws -> String? {
        do {
            return try storage.load(forKey: tokenKey)
        } catch SecureStorageError.itemNotFound {
            return nil
        }
    }

    func delete() throws {
        storage.delete(forKey: tokenKey)
        logger.debug("Slack Bot Token deleted")
    }
}

// MARK: - Convenience

extension SlackKeychainStorage {
    var hasToken: Bool {
        storage.contains(key: tokenKey)
    }
}
