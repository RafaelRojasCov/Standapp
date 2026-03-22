import Foundation
import Security
import CryptoKit
import OSLog

// MARK: - SecureStorageService
//
// Strategy: store a single AES-256-GCM master key in the Keychain (one prompt, ever).
// All credentials are encrypted with that key and persisted in UserDefaults — no further
// Keychain prompts are shown after the first launch.

final class SecureStorageService: @unchecked Sendable {

    static let shared = SecureStorageService()

    private let masterKeyService  = "com.standapp.masterkey"
    private let masterKeyAccount  = "masterEncryptionKey"
    private let userDefaultsKey   = "com.standapp.secureStore"
    private let logger = Logger(subsystem: "com.standapp", category: "SecureStorage")

    private init() {}

    /// Call at app launch to trigger the Keychain prompt (if needed) before any credential
    /// operation occurs. After the first call the master key is cached by the OS and no
    /// further prompts are shown.
    func warmUp() {
        _ = try? resolvedMasterKey()
    }

    // MARK: - Public API

    func save(_ value: String, forKey key: String) throws {
        let masterKey = try resolvedMasterKey()

        guard let plaintext = value.data(using: .utf8) else {
            throw SecureStorageError.encodingFailed
        }

        let sealedBox = try AES.GCM.seal(plaintext, using: masterKey)
        guard let combined = sealedBox.combined else {
            throw SecureStorageError.encryptionFailed
        }

        var store = loadStore()
        store[key] = combined.base64EncodedString()
        saveStore(store)
        logger.debug("SecureStorage: saved key '\(key)'")
    }

    func load(forKey key: String) throws -> String {
        let masterKey = try resolvedMasterKey()

        let store = loadStore()
        guard let encoded = store[key],
              let combined = Data(base64Encoded: encoded) else {
            throw SecureStorageError.itemNotFound
        }

        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealedBox, using: masterKey)

        guard let value = String(data: plaintext, encoding: .utf8) else {
            throw SecureStorageError.decodingFailed
        }

        return value
    }

    func delete(forKey key: String) {
        var store = loadStore()
        store.removeValue(forKey: key)
        saveStore(store)
        logger.debug("SecureStorage: deleted key '\(key)'")
    }

    func contains(key: String) -> Bool {
        let store = loadStore()
        return store[key] != nil
    }

    // MARK: - Master Key Management

    /// Returns the master key, creating and storing it in the Keychain on first use.
    /// This is the only Keychain operation — it happens once per device, ever.
    private func resolvedMasterKey() throws -> SymmetricKey {
        if let existing = try? loadMasterKeyFromKeychain() {
            return existing
        }
        let newKey = SymmetricKey(size: .bits256)
        try saveMasterKeyToKeychain(newKey)
        logger.debug("SecureStorage: master key created and stored in Keychain")
        return newKey
    }

    private func loadMasterKeyFromKeychain() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: masterKeyService,
            kSecAttrAccount as String: masterKeyAccount,
            kSecMatchLimit as String:  kSecMatchLimitOne,
            kSecReturnData as String:  kCFBooleanTrue as Any
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw SecureStorageError.unexpectedKeychainData
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            throw SecureStorageError.itemNotFound
        default:
            logger.error("SecureStorage: Keychain load failed (\(status))")
            throw SecureStorageError.keychainError(status: status)
        }
    }

    private func saveMasterKeyToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        // Try update first; add if not found.
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: masterKeyService,
            kSecAttrAccount as String: masterKeyAccount
        ]
        let attributes: [CFString: Any] = [kSecValueData: keyData]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = keyData
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("SecureStorage: Keychain add failed (\(addStatus))")
                throw SecureStorageError.keychainError(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            logger.error("SecureStorage: Keychain update failed (\(updateStatus))")
            throw SecureStorageError.keychainError(status: updateStatus)
        }
    }

    // MARK: - UserDefaults Store

    private func loadStore() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let store = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return store
    }

    private func saveStore(_ store: [String: String]) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}

// MARK: - Errors

enum SecureStorageError: LocalizedError {
    case itemNotFound
    case encodingFailed
    case decodingFailed
    case encryptionFailed
    case unexpectedKeychainData
    case keychainError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:            return "Secure storage item not found."
        case .encodingFailed:          return "Failed to encode value."
        case .decodingFailed:          return "Failed to decode stored value."
        case .encryptionFailed:        return "Encryption failed."
        case .unexpectedKeychainData:  return "Unexpected Keychain data format."
        case .keychainError(let s):    return "Keychain error (OSStatus \(s))."
        }
    }
}
