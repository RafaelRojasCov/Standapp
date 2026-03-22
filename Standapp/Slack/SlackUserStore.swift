import Foundation
import Observation
import OSLog

/// Singleton that holds the workspace user list.
/// Loads once per session; callers can call `loadIfNeeded()` any time.
@MainActor
@Observable
final class SlackUserStore {

    static let shared = SlackUserStore()

    private(set) var users: [SlackUser] = []
    private(set) var isLoading = false
    private var loaded = false

    private let network: any SlackNetworkService
    private let logger = Logger(subsystem: "com.standapp", category: "SlackUserStore")

    private init(network: any SlackNetworkService = SlackNetworkServiceImpl()) {
        self.network = network
    }

    func loadIfNeeded() async {
        guard !loaded, !isLoading else { return }
        isLoading = true
        do {
            users = try await network.fetchUsers()
            loaded = true
            logger.debug("Loaded \(self.users.count) workspace users")
        } catch {
            logger.error("Failed to load users: \(error.localizedDescription)")
        }
        isLoading = false
    }

    /// Returns users whose username starts with or contains the query (case-insensitive).
    func filter(_ query: String) -> [SlackUser] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter { $0.username.lowercased().contains(q) }
    }
}
