import Foundation
import OSLog
import Observation

// MARK: - Loading State

enum JiraLoadingState: Equatable {
    case idle
    case loading
    case loadingMore
    case loaded
    case error(String)
}

// MARK: - ViewModel

@MainActor
@Observable
final class JiraViewModel {

    // MARK: - Published State

    var tickets: [JiraTicket] = []
    var selectedTicketIDs: Set<String> = []
    var searchQuery: String = "" {
        didSet { scheduleSearch() }
    }
    var loadingState: JiraLoadingState = .idle
    var alertError: JiraError?
    var showAlert: Bool = false

    // MARK: - Pagination

    private(set) var nextPageToken: String? = nil
    private let pageSize: Int = 25

    var hasMorePages: Bool { nextPageToken != nil }

    // MARK: - Dependencies

    private let networkService: any JiraNetworkServiceProtocol
    private let keychain: KeychainManager
    private let logger = Logger(subsystem: "com.standapp", category: "JiraViewModel")

    // MARK: - Debounce

    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: UInt64 = 400_000_000  // 400ms in nanoseconds

    // MARK: - Init

    init(
        networkService: any JiraNetworkServiceProtocol = JiraNetworkService(),
        keychain: KeychainManager = .shared
    ) {
        self.networkService = networkService
        self.keychain = keychain
    }

    // MARK: - Search

    /// Cancels any pending debounce and schedules a new search after the delay.
    func scheduleSearch() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
                await self.performSearch(resetPagination: true)
            } catch {
                // Task was cancelled — no-op
            }
        }
    }

    /// Immediately executes a search, resetting pagination state.
    func performSearch(resetPagination: Bool = true) async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            tickets = []
            nextPageToken = nil
            loadingState = .idle
            return
        }

        guard keychain.hasJiraCredentials else {
            present(error: .missingCredentials)
            return
        }

        if resetPagination {
            nextPageToken = nil
            tickets = []
        }

        loadingState = .loading
        logger.debug("Search: '\(self.searchQuery)'")

        let jql = buildJQL(from: searchQuery)

        do {
            let response = try await networkService.search(
                jql: jql,
                nextPageToken: resetPagination ? nil : nextPageToken,
                maxResults: pageSize
            )
            let newTickets = response.issues.map { $0.toTicket() }
            tickets = resetPagination ? newTickets : tickets + newTickets
            nextPageToken = response.nextPageToken
            loadingState = .loaded
            logger.debug("Loaded \(newTickets.count) tickets, hasMore=\(response.nextPageToken != nil)")
        } catch let error as JiraError {
            loadingState = .error(error.localizedDescription)
            present(error: error)
        } catch {
            let msg = error.localizedDescription
            loadingState = .error(msg)
            logger.error("Unexpected error: \(msg)")
        }
    }

    // MARK: - Infinite Scroll

    /// Call this when the last visible ticket appears on screen.
    func loadMoreIfNeeded(currentItem ticket: JiraTicket) async {
        guard
            hasMorePages,
            loadingState != .loadingMore,
            let lastID = tickets.last?.id,
            ticket.id == lastID
        else { return }

        loadingState = .loadingMore
        logger.debug("Loading more tickets with nextPageToken=\(self.nextPageToken ?? "nil")")

        let jql = buildJQL(from: searchQuery)

        do {
            let response = try await networkService.search(
                jql: jql,
                nextPageToken: nextPageToken,
                maxResults: pageSize
            )
            let newTickets = response.issues.map { $0.toTicket() }
            tickets.append(contentsOf: newTickets)
            nextPageToken = response.nextPageToken
            loadingState = .loaded
        } catch let error as JiraError {
            loadingState = .error(error.localizedDescription)
            present(error: error)
        } catch {
            loadingState = .loaded
            logger.error("Pagination error: \(error.localizedDescription)")
        }
    }

    // MARK: - URL Generation

    func browseURL(for ticket: JiraTicket) -> URL? {
        try? keychain.loadJiraCredentials().browseURL(for: ticket.id)
    }

    // MARK: - Selection

    func copySelectedKeys() -> String {
        tickets
            .filter { selectedTicketIDs.contains($0.id) }
            .map { $0.id }
            .joined(separator: ", ")
    }

    func clearSelection() {
        selectedTicketIDs = []
    }

    // MARK: - Credentials

    func saveCredentials(subdomain: String, email: String, apiToken: String) {
        let credentials = JiraCredentials(subdomain: subdomain, email: email, apiToken: apiToken)
        do {
            try keychain.saveJiraCredentials(credentials)
            logger.debug("Jira credentials saved")
        } catch {
            present(error: .authFailed)
        }
    }

    func deleteCredentials() {
        keychain.deleteJiraCredentials()
    }

    func loadStoredCredentials() -> JiraCredentials? {
        try? keychain.loadJiraCredentials()
    }

    // MARK: - Helpers

    private func buildJQL(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // Detect JQL by looking for keywords as whole words/tokens, not substrings.
        // e.g. "Vendedor" must NOT match because it contains "OR" mid-word.
        let jqlPattern = #"\b(AND|OR|NOT|ORDER\s+BY|project\s*=|status\s*=|assignee\s*=)\b"#
        let looksLikeJQL = trimmed.range(
            of: jqlPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if looksLikeJQL {
            return trimmed
        }
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
        return "text ~ \"\(escaped)\" ORDER BY updated DESC"
    }

    private func present(error: JiraError) {
        alertError = error
        showAlert = true
    }
}
