import Foundation
import OSLog

// MARK: - Error Types

enum SlackError: LocalizedError, Equatable {
    case unauthorized
    case rateLimitExceeded
    case rateLimited(retryAfter: TimeInterval)
    case networkTimeout
    case invalidResponse(statusCode: Int)
    case decodingFailed(underlying: String)
    case missingCredentials
    case sandboxEntitlementMissing
    case apiError(message: String)

    static func == (lhs: SlackError, rhs: SlackError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.rateLimitExceeded, .rateLimitExceeded): return true
        case (.rateLimited(let a), .rateLimited(let b)): return a == b
        case (.networkTimeout, .networkTimeout): return true
        case (.invalidResponse(let a), .invalidResponse(let b)): return a == b
        case (.decodingFailed(let a), .decodingFailed(let b)): return a == b
        case (.missingCredentials, .missingCredentials): return true
        case (.sandboxEntitlementMissing, .sandboxEntitlementMissing): return true
        case (.apiError(let a), .apiError(let b)): return a == b
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Slack token is invalid or has been revoked."
        case .rateLimitExceeded:
            return "Slack rate limit exceeded after maximum retries."
        case .rateLimited(let seconds):
            return "Rate limited by Slack. Retry after \(Int(seconds))s."
        case .networkTimeout:
            return "Request timed out. Check your network connection."
        case .invalidResponse(let code):
            return "Unexpected server response (HTTP \(code))."
        case .decodingFailed:
            return "Failed to parse Slack response."
        case .missingCredentials:
            return "Slack Bot Token not configured. Open Settings to add it."
        case .sandboxEntitlementMissing:
            return "Keychain access denied — missing entitlement."
        case .apiError(let message):
            return "Slack API error: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unauthorized, .missingCredentials:
            return "Open Settings and enter your Slack Bot Token."
        case .rateLimitExceeded:
            return "Wait a moment and try again."
        case .sandboxEntitlementMissing:
            return "Check app entitlements in the project settings."
        default:
            return nil
        }
    }
}

// MARK: - Domain Types

/// A Slack channel (public or private) the bot has access to.
struct SlackChannel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

/// A single Slack message, mapping `ts` → `id`.
struct SlackMessage: Codable, Identifiable, Hashable {
    let id: String          // mapped from `ts`
    let text: String
    let threadTs: String?   // mapped from `thread_ts`

    enum CodingKeys: String, CodingKey {
        case id = "ts"
        case text
        case threadTs = "thread_ts"
    }
}

/// A Slack workspace member (used for @mention autocomplete).
struct SlackUser: Identifiable, Hashable, Codable {
    let id: String          // Slack user ID, e.g. "U01ABC123"
    let username: String    // display_name or real_name
    let isBot: Bool

    /// The mrkdwn mention string sent to Slack.
    var mention: String { "<@\(id)>" }

    /// The display string shown in the app preview.
    var atHandle: String { "@\(username)" }
}

/// Top-level response from `users.list`.
struct SlackUsersListResponse: Decodable {
    let ok: Bool
    let members: [SlackUserRaw]?
    let error: String?
    let responseMetadata: SlackResponseMetadata?

    enum CodingKeys: String, CodingKey {
        case ok, members, error
        case responseMetadata = "response_metadata"
    }
}

struct SlackUserRaw: Decodable {
    let id: String
    let isBot: Bool
    let deleted: Bool
    let profile: SlackUserProfile

    enum CodingKeys: String, CodingKey {
        case id
        case isBot   = "is_bot"
        case deleted
        case profile
    }

    func toUser() -> SlackUser? {
        guard !deleted, !isBot else { return nil }
        let name = profile.displayName.isEmpty ? profile.realName : profile.displayName
        guard !name.isEmpty else { return nil }
        return SlackUser(id: id, username: name, isBot: false)
    }
}

struct SlackUserProfile: Decodable {
    let displayName: String
    let realName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case realName    = "real_name"
    }
}

/// Identifies where a dispatched message should land.
enum DestinationType: Equatable {
    case channel(id: String)
    case thread(channelId: String, ts: String)
}

/// The ViewModel's loading/dispatch lifecycle.
enum DispatchState: Equatable {
    case idle
    case fetching
    case sending
    case error(SlackError)
}

// MARK: - Raw Decodable Wrappers

/// Top-level response from `conversations.list`.
struct SlackConversationsListResponse: Decodable {
    let ok: Bool
    let channels: [SlackChannelRaw]?
    let error: String?
    let responseMetadata: SlackResponseMetadata?

    enum CodingKeys: String, CodingKey {
        case ok, channels, error
        case responseMetadata = "response_metadata"
    }
}

struct SlackChannelRaw: Decodable {
    let id: String
    let name: String

    func toChannel() -> SlackChannel {
        SlackChannel(id: id, name: name)
    }
}

struct SlackResponseMetadata: Decodable {
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case nextCursor = "next_cursor"
    }
}

/// A channel message that is the root of a thread (reply_count > 0).
/// Used in the thread picker to show sender + message text.
struct SlackThreadMessage: Identifiable, Hashable {
    let id: String      // ts
    let userId: String
    let username: String
    let text: String
}

/// Top-level response from `conversations.history`.
struct SlackHistoryResponse: Decodable {
    let ok: Bool
    let messages: [SlackHistoryMessageRaw]?
    let error: String?
    let responseMetadata: SlackResponseMetadata?

    enum CodingKeys: String, CodingKey {
        case ok, messages, error
        case responseMetadata = "response_metadata"
    }
}

struct SlackHistoryMessageRaw: Decodable {
    let ts: String
    let user: String?
    let username: String?
    let text: String?
    let replyCount: Int?

    enum CodingKeys: String, CodingKey {
        case ts, user, username, text
        case replyCount = "reply_count"
    }

    /// Returns a SlackThreadMessage only when this message has at least one reply.
    /// `resolvedUsername` is looked up from the cached user store when available.
    func toThreadMessage(resolvedUsername: String? = nil) -> SlackThreadMessage? {
        guard let count = replyCount, count > 0 else { return nil }
        // Priority: store lookup → username field (bots/webhooks) → user ID as fallback
        let displayName = resolvedUsername ?? username ?? user ?? "Unknown"
        return SlackThreadMessage(
            id: ts,
            userId: user ?? "",
            username: displayName,
            text: SlackTextParser.parse(text ?? "(no text)")
        )
    }
}

// MARK: - Slack Text Parser

/// Converts Slack mrkdwn encoding back to human-readable text for display in the app.
enum SlackTextParser {
    static func parse(_ text: String) -> String {
        var result = text

        // Special broadcasts
        result = result.replacingOccurrences(of: "<!here>",    with: "@here")
        result = result.replacingOccurrences(of: "<!here|here>", with: "@here")
        result = result.replacingOccurrences(of: "<!channel>", with: "@channel")
        result = result.replacingOccurrences(of: "<!channel|channel>", with: "@channel")
        result = result.replacingOccurrences(of: "<!everyone>", with: "@everyone")

        // User mentions <@U123|name> → @name, <@U123> → @U123
        result = result.replacingOccurrences(
            of: #"<@([A-Z0-9]+)\|([^>]+)>"#,
            with: "@$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<@([A-Z0-9]+)>"#,
            with: "@$1",
            options: .regularExpression
        )

        // Links <url|label> → label, <url> → url
        result = result.replacingOccurrences(
            of: #"<([^|>]+)\|([^>]+)>"#,
            with: "$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<(https?://[^>]+)>"#,
            with: "$1",
            options: .regularExpression
        )

        return result
    }
}

/// Top-level response from `conversations.replies`.
struct SlackRepliesResponse: Decodable {
    let ok: Bool
    let messages: [SlackMessage]?
    let error: String?
}

/// Top-level response from `chat.postMessage`.
struct SlackPostMessageResponse: Decodable {
    let ok: Bool
    let ts: String?
    let error: String?
}
