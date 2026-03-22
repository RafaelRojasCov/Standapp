import Foundation
import OSLog
import Observation

// MARK: - ViewModel (A-SPEC: @MainActor isolated)

@MainActor
@Observable
final class SlackViewModel {

    // MARK: - Published State

    /// All channels loaded so far (capped at 5,000 — F-SPEC 3.2).
    private(set) var channels: [SlackChannel] = []

    /// Channels matching the current search query (client-side filter).
    private(set) var filteredChannels: [SlackChannel] = []

    /// Current lifecycle state.
    var dispatchState: DispatchState = .idle

    /// Alert presentation.
    var alertError: SlackError?
    var showAlert = false

    /// Whether to navigate to SettingsView (EC-401 routing).
    var shouldRouteToSettings = false

    // MARK: - Search

    var searchQuery: String = "" {
        didSet { scheduleSearchDebounce() }
    }

    // MARK: - Dispatch Sheet

    /// The text to be dispatched.
    var messageText: String = ""

    /// Where to send (channel or thread).
    var destination: DestinationType?

    /// Selected channel in the picker.
    var selectedChannel: SlackChannel?

    /// Thread ts input (when dispatching to a thread).
    var threadTs: String = ""

    /// Whether the sheet stays open after a successful send (multi-dispatch mode).
    var isMultiDispatch: Bool = false

    /// Tracks last-sent success briefly for UI feedback.
    var didSendSuccessfully = false

    // MARK: - Pagination

    private(set) var nextCursor: String?
    private let maxChannelsInMemory = 5_000
    private let pageSize = 200    // F-SPEC: 200 per request

    var hasMorePages: Bool { nextCursor != nil }

    // MARK: - Dependencies

    private let networkService: any SlackNetworkService
    private let keychain: any KeychainStorage
    private let logger = Logger(subsystem: "com.standapp", category: "SlackViewModel")

    // MARK: - Debounce

    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: UInt64 = 350_000_000   // 350ms — within F-SPEC 300-500ms window

    // MARK: - Init

    init(
        networkService: any SlackNetworkService = SlackNetworkServiceImpl(),
        keychain: any KeychainStorage = SlackKeychainStorage.shared
    ) {
        self.networkService = networkService
        self.keychain = keychain
    }

    // MARK: - Channel Loading

    /// Loads the first page of channels, resetting any existing state.
    func loadChannels() async {
        guard dispatchState != .fetching else { return }

        guard (try? keychain.retrieve()) != nil else {
            present(error: .missingCredentials)
            return
        }

        channels = []
        nextCursor = nil
        dispatchState = .fetching
        logger.debug("Loading channels (first page)")

        await fetchNextPage()
    }

    /// Loads the next page and appends — call from infinite scroll trigger.
    func loadMoreChannelsIfNeeded(currentItem channel: SlackChannel) async {
        guard
            hasMorePages,
            dispatchState != .fetching,
            let lastId = channels.last?.id,
            channel.id == lastId
        else { return }

        logger.debug("Loading next page of channels, cursor=\(self.nextCursor ?? "nil")")
        dispatchState = .fetching
        await fetchNextPage()
    }

    // MARK: - Message Dispatch

    /// Sends `messageText` to the resolved `DestinationType`.
    func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let dest: DestinationType
        if !threadTs.isEmpty, let channel = selectedChannel {
            dest = .thread(channelId: channel.id, ts: threadTs)
        } else if let channel = selectedChannel {
            dest = .channel(id: channel.id)
        } else if let explicit = destination {
            dest = explicit
        } else {
            return
        }

        dispatchState = .sending
        logger.debug("Dispatching message to \(String(describing: dest))")

        do {
            _ = try await networkService.dispatchMessage(to: dest, text: text)
            logger.debug("Message dispatched successfully")
            didSendSuccessfully = true

            if isMultiDispatch {
                // F-SPEC 3.3: reset input but keep sheet open
                messageText = ""
                threadTs = ""
                didSendSuccessfully = false
            }
            dispatchState = .idle
        } catch let error as SlackError {
            handle(error: error)
        } catch {
            dispatchState = .error(.apiError(message: error.localizedDescription))
        }
    }

    // MARK: - Thread Replies

    func loadThreadReplies(channelId: String, ts: String) async -> [SlackMessage] {
        do {
            return try await networkService.fetchThreadReplies(channelId: channelId, ts: ts)
        } catch let error as SlackError {
            handle(error: error)
            return []
        } catch {
            return []
        }
    }

    // MARK: - Credential Management

    func saveToken(_ token: String) {
        do {
            try keychain.save(token: token)
            logger.debug("Slack token saved")
        } catch {
            present(error: .apiError(message: error.localizedDescription))
        }
    }

    func deleteToken() {
        try? keychain.delete()
        logger.debug("Slack token deleted")
    }

    var hasToken: Bool {
        (try? keychain.retrieve().map { !$0.isEmpty }) ?? false
    }

    // MARK: - Private Helpers

    private func fetchNextPage() async {
        do {
            let result = try await networkService.fetchChannels(cursor: nextCursor)
            let incoming = result.channels

            // F-SPEC: cap at 5,000 items in memory
            let remaining = maxChannelsInMemory - channels.count
            let toAppend = remaining > 0 ? Array(incoming.prefix(remaining)) : []
            channels.append(contentsOf: toAppend)

            // Stop pagination if cap reached
            nextCursor = channels.count >= maxChannelsInMemory ? nil : result.nextCursor

            applyFilter()
            dispatchState = .idle
            logger.debug("Loaded \(incoming.count) channels (total=\(self.channels.count), hasMore=\(self.nextCursor != nil))")
        } catch let error as SlackError {
            handle(error: error)
        } catch {
            dispatchState = .error(.apiError(message: error.localizedDescription))
            logger.error("Unexpected error loading channels: \(error.localizedDescription)")
        }
    }

    // MARK: - Search / Filter (F-SPEC 3.3: debounced 300-500ms)

    private func scheduleSearchDebounce() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
                self.applyFilter()
            } catch {
                // Cancelled — no-op
            }
        }
    }

    private func applyFilter() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            filteredChannels = channels
        } else {
            filteredChannels = channels.filter { $0.name.lowercased().contains(query) }
        }
    }

    // MARK: - Error Handling

    private func handle(error: SlackError) {
        switch error {
        case .unauthorized:
            // EC-401: clear token and route to Settings
            logger.warning("Slack 401 — clearing token and routing to Settings")
            try? keychain.delete()
            shouldRouteToSettings = true
            dispatchState = .error(error)
            present(error: error)

        case .rateLimitExceeded:
            // EC-429: aborted after 3 retries
            logger.error("Slack rate limit exceeded after max retries")
            dispatchState = .error(error)
            present(error: error)

        default:
            dispatchState = .error(error)
            present(error: error)
        }
    }

    private func present(error: SlackError) {
        alertError = error
        showAlert = true
    }
}
