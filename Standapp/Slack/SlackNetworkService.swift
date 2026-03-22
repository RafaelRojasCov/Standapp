import Foundation
import OSLog

// MARK: - Protocol (I-SPEC)

protocol SlackNetworkService: Sendable {
    func fetchChannels(cursor: String?) async throws -> (channels: [SlackChannel], nextCursor: String?)
    func fetchChannelHistory(channelId: String, oldestTimestamp: TimeInterval) async throws -> [SlackThreadMessage]
    func fetchThreadReplies(channelId: String, ts: String) async throws -> [SlackMessage]
    func dispatchMessage(to destination: DestinationType, text: String) async throws -> Bool
}

// MARK: - Background Actor for JSON Parsing (A-SPEC)

private actor JSONParsingActor {
    func decodeChannelsList(data: Data) throws -> SlackConversationsListResponse {
        try JSONDecoder().decode(SlackConversationsListResponse.self, from: data)
    }

    func decodeReplies(data: Data) throws -> SlackRepliesResponse {
        try JSONDecoder().decode(SlackRepliesResponse.self, from: data)
    }

    func decodePostMessage(data: Data) throws -> SlackPostMessageResponse {
        try JSONDecoder().decode(SlackPostMessageResponse.self, from: data)
    }
}

// MARK: - Concrete Implementation

final class SlackNetworkServiceImpl: SlackNetworkService, @unchecked Sendable {

    private let keychain: any KeychainStorage
    private let session: URLSession
    private let logger = Logger(subsystem: "com.standapp", category: "SlackNetwork")
    private let jsonParser = JSONParsingActor()

    private let baseURL = URL(string: "https://slack.com/api")!
    private let requestTimeout: TimeInterval = 15
    private let maxRetries = 3

    init(
        keychain: any KeychainStorage = SlackKeychainStorage.shared,
        session: URLSession = .shared
    ) {
        self.keychain = keychain
        self.session = session
    }

    // MARK: - SlackNetworkService

    /// Fetches one page of channels from `conversations.list` (limit 200 per page).
    func fetchChannels(cursor: String?) async throws -> (channels: [SlackChannel], nextCursor: String?) {
        let token = try resolvedToken()

        var components = URLComponents(url: baseURL.appendingPathComponent("conversations.list"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "exclude_archived", value: "true"),
            URLQueryItem(name: "types", value: "public_channel")
        ]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!, timeoutInterval: requestTimeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        logger.debug("GET conversations.list cursor=\(cursor ?? "initial")")

        let data = try await performWithRateLimit(request: request)

        // EC-MassivePayload: offload to background actor
        let response = try await jsonParser.decodeChannelsList(data: data)

        if !response.ok {
            throw SlackError.apiError(message: response.error ?? "unknown")
        }

        let channels = (response.channels ?? []).map { $0.toChannel() }
        let next = response.responseMetadata?.nextCursor.flatMap { $0.isEmpty ? nil : $0 }

        return (channels, next)
    }

    /// Fetches recent messages from a channel that have at least one reply (thread roots).
    /// `oldestTimestamp` limits results — pass `Date().timeIntervalSince1970 - 86400` for 24h.
    func fetchChannelHistory(channelId: String, oldestTimestamp: TimeInterval) async throws -> [SlackThreadMessage] {
        let token = try resolvedToken()

        var components = URLComponents(url: baseURL.appendingPathComponent("conversations.history"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "channel", value: channelId),
            URLQueryItem(name: "oldest",  value: String(oldestTimestamp)),
            URLQueryItem(name: "limit",   value: "100")
        ]

        var request = URLRequest(url: components.url!, timeoutInterval: requestTimeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        logger.debug("GET conversations.history channel=\(channelId)")

        let data = try await performWithRateLimit(request: request)
        let response = try JSONDecoder().decode(SlackHistoryResponse.self, from: data)

        if !response.ok {
            throw SlackError.apiError(message: response.error ?? "unknown")
        }

        return (response.messages ?? []).compactMap { $0.toThreadMessage() }
    }

    /// Fetches all replies in a thread via `conversations.replies`.
    func fetchThreadReplies(channelId: String, ts: String) async throws -> [SlackMessage] {
        let token = try resolvedToken()

        var components = URLComponents(url: baseURL.appendingPathComponent("conversations.replies"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "channel", value: channelId),
            URLQueryItem(name: "ts", value: ts)
        ]

        var request = URLRequest(url: components.url!, timeoutInterval: requestTimeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        logger.debug("GET conversations.replies channel=\(channelId) ts=\(ts)")

        let data = try await performWithRateLimit(request: request)

        // EC-MassivePayload: large threads offloaded to background actor (> ~1 MB triggers
        // actor scheduling on a non-main thread automatically via Swift concurrency).
        let response = try await jsonParser.decodeReplies(data: data)

        if !response.ok {
            throw SlackError.apiError(message: response.error ?? "unknown")
        }

        return response.messages ?? []
    }

    /// Converts a Markdown string (as produced by StandupFormatter) into Slack mrkdwn.
    /// Rules:
    ///   [label](url)  →  <url|label>   (links — must run before bold to avoid eating brackets)
    ///   **text**      →  *text*        (bold)
    private func markdownToMrkdwn(_ markdown: String) -> String {
        // 1. Convert Markdown links [label](url) → Slack <url|label>
        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        var result = markdown.replacingOccurrences(
            of: linkPattern,
            with: "<$2|$1>",
            options: .regularExpression
        )
        // 2. Convert **bold** → *bold*
        let boldPattern = #"\*\*(.+?)\*\*"#
        result = result.replacingOccurrences(
            of: boldPattern,
            with: "*$1*",
            options: .regularExpression
        )
        return result
    }

    /// Posts a message via `chat.postMessage`. Returns true on success.
    func dispatchMessage(to destination: DestinationType, text: String) async throws -> Bool {
        let token = try resolvedToken()
        let mrkdwn = markdownToMrkdwn(text)

        var body: [String: Any]
        switch destination {
        case .channel(let id):
            body = ["channel": id, "text": mrkdwn, "mrkdwn": true]
        case .thread(let channelId, let ts):
            body = ["channel": channelId, "thread_ts": ts, "text": mrkdwn, "mrkdwn": true]
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat.postMessage"), timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.debug("POST chat.postMessage destination=\(String(describing: destination))")

        let data = try await performWithRateLimit(request: request)
        let response = try await jsonParser.decodePostMessage(data: data)

        if !response.ok {
            throw SlackError.apiError(message: response.error ?? "unknown")
        }

        return true
    }

    // MARK: - Rate Limit + Retry (F-SPEC 3.2)

    /// Executes the request, transparently retrying on HTTP 429 up to `maxRetries` times.
    private func performWithRateLimit(request: URLRequest, attempt: Int = 0) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw SlackError.invalidResponse(statusCode: -1)
            }

            switch http.statusCode {
            case 200:
                return data

            case 401:
                // EC-401: Token revocation — caller must clear Keychain and route to Settings.
                logger.warning("Slack 401: token revoked or invalid")
                throw SlackError.unauthorized

            case 429:
                let delay = retryAfter(from: http, attempt: attempt)
                logger.warning("Slack 429 rate limit — retry after \(delay)s (attempt \(attempt + 1)/\(self.maxRetries))")

                guard attempt < maxRetries else {
                    throw SlackError.rateLimitExceeded
                }

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performWithRateLimit(request: request, attempt: attempt + 1)

            default:
                logger.error("Slack unexpected HTTP \(http.statusCode)")
                throw SlackError.invalidResponse(statusCode: http.statusCode)
            }

        } catch let error as URLError where error.code == .timedOut {
            throw SlackError.networkTimeout
        } catch let slackError as SlackError {
            throw slackError
        } catch {
            throw error
        }
    }

    /// Parses `Retry-After` header (seconds); falls back to exponential back-off.
    private func retryAfter(from response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(header) {
            return seconds
        }
        return pow(2.0, Double(attempt)) // 1s, 2s, 4s
    }

    // MARK: - Credential Helper

    private func resolvedToken() throws -> String {
        guard let token = try keychain.retrieve(), !token.isEmpty else {
            throw SlackError.missingCredentials
        }
        return token
    }
}
