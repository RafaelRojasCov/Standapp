import Foundation
import AppKit
import Combine

@MainActor
final class JiraViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var tickets: [JiraTicket] = []
    @Published var selectedTicketIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isFetchingMore = false
    @Published private(set) var totalResults: Int = 0

    private let apiService: JiraAPIService
    private var debounceTask: Task<Void, Never>?
    private var currentOffset = 0
    private var currentQuery = ""

    init(apiService: JiraAPIService = JiraAPIService()) {
        self.apiService = apiService
    }

    func updateSearchText(_ value: String, subdomain: String) {
        searchText = value
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            await self.runFreshSearch(subdomain: subdomain)
        }
    }

    func fetchNextPageIfNeeded(currentTicket: JiraTicket, subdomain: String) async {
        guard let last = tickets.last, last.id == currentTicket.id else { return }
        guard !isFetchingMore, !isLoading else { return }
        guard tickets.count < totalResults else { return }
        await fetchPage(subdomain: subdomain, reset: false)
    }

    func openSelectedInBrowser(subdomain: String) {
        let selectedTickets = tickets.filter { selectedTicketIDs.contains($0.id) }
        guard !selectedTickets.isEmpty else { return }

        let normalized = subdomain.jiraNormalizedSubdomain
        guard !normalized.isEmpty else {
            errorMessage = "Invalid or empty Jira subdomain. Verify your Settings value."
            return
        }

        var failures: [String] = []
        for ticket in selectedTickets {
            guard let url = URL(string: "https://\(normalized).atlassian.net/browse/\(ticket.key)") else {
                failures.append(ticket.key)
                continue
            }
            if !NSWorkspace.shared.open(url) {
                failures.append(ticket.key)
            }
        }

        if !failures.isEmpty {
            errorMessage = "Could not open browser for: \(failures.joined(separator: ", "))."
        }
    }

    private func runFreshSearch(subdomain: String) async {
        currentOffset = 0
        totalResults = 0
        currentQuery = buildJQL(searchText)
        await fetchPage(subdomain: subdomain, reset: true)
    }

    private func fetchPage(subdomain: String, reset: Bool) async {
        let normalized = subdomain.jiraNormalizedSubdomain
        guard !normalized.isEmpty else {
            tickets = []
            selectedTicketIDs.removeAll()
            return
        }
        if reset {
            isLoading = true
        } else {
            isFetchingMore = true
        }
        defer {
            isLoading = false
            isFetchingMore = false
        }

        do {
            let response = try await apiService.searchTickets(
                subdomain: normalized,
                jql: currentQuery,
                startAt: currentOffset,
                maxResults: 50
            )
            totalResults = response.total
            currentOffset = response.startAt + response.issues.count
            if reset {
                tickets = response.issues
                selectedTicketIDs.removeAll()
            } else {
                tickets.append(contentsOf: response.issues)
            }
            errorMessage = nil
        } catch let error as JiraError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = JiraError.unknown.errorDescription
        }
    }

    private func buildJQL(_ text: String) -> String {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty {
            return "assignee = currentUser() ORDER BY updated DESC"
        }
        let escaped = term.replacingOccurrences(of: "\"", with: "\\\"")
        return "assignee = currentUser() AND (summary ~ \"*\(escaped)*\" OR key = \"\(escaped)\")"
    }

}
