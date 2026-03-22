import Foundation
import OSLog
import Observation

// MARK: - Destination Mode

enum DispatchDestinationMode: Equatable {
    case channel
    case thread
}

// MARK: - SlackDispatchViewModel

@MainActor
@Observable
final class SlackDispatchViewModel {

    // MARK: - Immutable input

    let messageText: String
    /// Tagged users from all standup items, used to resolve @username → <@userId> before dispatch.
    let taggedUsers: [TaggedUser]

    // MARK: - Destination selection

    var destinationMode: DispatchDestinationMode = .channel

    /// Selected channel (shared by both flows).
    var selectedChannel: SlackChannel? {
        didSet {
            // When a channel is selected in thread mode, auto-load its thread roots.
            if destinationMode == .thread, let channel = selectedChannel {
                selectedThread = nil
                threadMessages = []
                filteredThreadMessages = []
                threadSearchQuery = ""
                Task { await loadThreadMessages(for: channel) }
            }
        }
    }

    /// Selected thread root message (thread flow only).
    var selectedThread: SlackThreadMessage?

    // MARK: - Channel search

    var channelSearchQuery: String = "" {
        didSet { scheduleChannelSearchDebounce() }
    }
    private(set) var filteredChannels: [SlackChannel] = []
    private var allChannels: [SlackChannel] = []
    private var nextCursor: String?
    private let maxChannels = 5_000

    // MARK: - Thread message list (thread flow, step 2)

    var threadSearchQuery: String = "" {
        didSet { scheduleThreadSearchDebounce() }
    }
    private(set) var threadMessages: [SlackThreadMessage] = []
    private(set) var filteredThreadMessages: [SlackThreadMessage] = []

    // MARK: - UI State

    private(set) var isLoadingChannels = false
    private(set) var isLoadingThreads = false
    private(set) var isSending = false
    var isMultiDispatchEnabled = false
    private(set) var didSendSuccessfully = false

    /// Inline error — does NOT dismiss modal.
    private(set) var inlineError: String?

    // MARK: - Debounce

    private var channelDebounceTask: Task<Void, Never>?
    private var threadDebounceTask: Task<Void, Never>?
    private let debounceDelay: UInt64 = 300_000_000  // 300ms

    // MARK: - Dependencies

    private let networkService: any SlackNetworkService
    private let logger = Logger(subsystem: "com.standapp", category: "SlackDispatchVM")

    // MARK: - Init

    init(
        messageText: String,
        taggedUsers: [TaggedUser] = [],
        networkService: any SlackNetworkService = SlackNetworkServiceImpl()
    ) {
        self.messageText = messageText
        self.taggedUsers = taggedUsers
        self.networkService = networkService
    }

    // MARK: - Derived: resolved DestinationType

    var resolvedDestination: DestinationType? {
        switch destinationMode {
        case .channel:
            guard let ch = selectedChannel else { return nil }
            return .channel(id: ch.id)
        case .thread:
            guard let ch = selectedChannel, let thread = selectedThread else { return nil }
            return .thread(channelId: ch.id, ts: thread.id)
        }
    }

    var canSend: Bool {
        resolvedDestination != nil && !isSending
    }

    // MARK: - Destination mode change

    func selectDestinationMode(_ mode: DispatchDestinationMode) {
        guard mode != destinationMode else { return }
        destinationMode = mode
        selectedChannel = nil
        selectedThread = nil
        threadMessages = []
        filteredThreadMessages = []
        threadSearchQuery = ""
        inlineError = nil
    }

    // MARK: - Channel Loading

    func loadChannels() async {
        guard !isLoadingChannels else { return }
        allChannels = []
        filteredChannels = []
        nextCursor = nil
        isLoadingChannels = true
        inlineError = nil
        await fetchChannelPage()
    }

    var hasMoreChannelPages: Bool { nextCursor != nil }

    func loadMoreChannelsIfNeeded(currentItem channel: SlackChannel) async {
        guard
            hasMoreChannelPages,
            !isLoadingChannels,
            let lastId = allChannels.last?.id,
            channel.id == lastId
        else { return }

        isLoadingChannels = true
        await fetchChannelPage()
    }

    private func fetchChannelPage() async {
        do {
            let result = try await networkService.fetchChannels(cursor: nextCursor)
            let incoming = result.channels
            let remaining = maxChannels - allChannels.count
            allChannels.append(contentsOf: incoming.prefix(remaining))
            nextCursor = allChannels.count >= maxChannels ? nil : result.nextCursor
            applyChannelFilter()
            isLoadingChannels = false
            logger.debug("Loaded \(incoming.count) channels (total \(self.allChannels.count))")
        } catch {
            isLoadingChannels = false
            inlineError = errorMessage(from: error)
            logger.error("Channel load error: \(error.localizedDescription)")
        }
    }

    // MARK: - Thread message loading (last 24h, roots only)

    private func loadThreadMessages(for channel: SlackChannel) async {
        guard !isLoadingThreads else { return }
        isLoadingThreads = true
        inlineError = nil

        let oldest = Date().timeIntervalSince1970 - 86_400  // last 24h

        do {
            let messages = try await networkService.fetchChannelHistory(
                channelId: channel.id,
                oldestTimestamp: oldest
            )
            threadMessages = messages
            applyThreadFilter()
            isLoadingThreads = false
            logger.debug("Loaded \(messages.count) thread roots for #\(channel.name)")
        } catch {
            isLoadingThreads = false
            inlineError = errorMessage(from: error)
            logger.error("Thread history error: \(error.localizedDescription)")
        }
    }

    // MARK: - Send

    func send() async {
        guard let destination = resolvedDestination, !isSending else { return }

        isSending = true
        inlineError = nil
        didSendSuccessfully = false

        // Resolve @username → <@userId> before dispatch
        let resolvedText = resolveMentions(in: messageText)

        do {
            _ = try await networkService.dispatchMessage(to: destination, text: resolvedText)
            isSending = false
            didSendSuccessfully = true
            logger.debug("Message dispatched to \(String(describing: destination))")

            if isMultiDispatchEnabled {
                selectedChannel = nil
                selectedThread = nil
                threadMessages = []
                filteredThreadMessages = []
                threadSearchQuery = ""
                channelSearchQuery = ""
                applyChannelFilter()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                didSendSuccessfully = false
            }
        } catch {
            isSending = false
            inlineError = errorMessage(from: error)
            logger.error("Send error: \(error.localizedDescription)")
        }
    }

    // MARK: - Channel search debounce

    private func scheduleChannelSearchDebounce() {
        channelDebounceTask?.cancel()
        channelDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
                self.applyChannelFilter()
            } catch {}
        }
    }

    private func applyChannelFilter() {
        let q = channelSearchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        filteredChannels = q.isEmpty
            ? allChannels
            : allChannels.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: - Thread search debounce

    private func scheduleThreadSearchDebounce() {
        threadDebounceTask?.cancel()
        threadDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
                self.applyThreadFilter()
            } catch {}
        }
    }

    private func applyThreadFilter() {
        let q = threadSearchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        filteredThreadMessages = q.isEmpty
            ? threadMessages
            : threadMessages.filter {
                $0.username.lowercased().contains(q) || $0.text.lowercased().contains(q)
            }
    }

    // MARK: - Helpers

    /// Replaces `@username` tokens with Slack `<@userId>` mentions using taggedUsers.
    private func resolveMentions(in text: String) -> String {
        var result = text
        for user in taggedUsers {
            result = result.replacingOccurrences(of: "@\(user.username)", with: "<@\(user.id)>")
        }
        return result
    }

    private func errorMessage(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
