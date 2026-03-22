import Foundation
import SwiftUI

// MARK: - Error Types

enum JiraError: LocalizedError {
    case rateLimited(retryAfter: TimeInterval)
    case invalidSubdomain
    case authFailed
    case networkTimeout
    case invalidResponse(statusCode: Int)
    case decodingFailed(underlying: Error)
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .rateLimited(let retryAfter):
            return "Rate limited by Jira. Retry after \(Int(retryAfter)) seconds."
        case .invalidSubdomain:
            return "Invalid Jira subdomain. Check your configuration."
        case .authFailed:
            return "Authentication failed. Verify your email and API token."
        case .networkTimeout:
            return "Request timed out. Check your network connection."
        case .invalidResponse(let code):
            return "Unexpected server response (HTTP \(code))."
        case .decodingFailed:
            return "Failed to parse Jira response."
        case .missingCredentials:
            return "Jira credentials not configured. Open Settings to add them."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .authFailed, .missingCredentials:
            return "Open Settings and enter your Jira subdomain, email, and API token."
        case .invalidSubdomain:
            return "The subdomain should be the part before .atlassian.net"
        default:
            return nil
        }
    }
}

// MARK: - Status Category

enum JiraStatusCategory: String, Decodable, Hashable {
    case toDo        = "To Do"
    case inProgress  = "In Progress"
    case done        = "Done"
    case undefined   = "undefined"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = JiraStatusCategory(rawValue: raw) ?? .undefined
    }

    var color: Color {
        switch self {
        case .toDo:       return Color(red: 0.55, green: 0.60, blue: 0.65)
        case .inProgress: return Color(red: 0.00, green: 0.45, blue: 0.89)
        case .done:       return Color(red: 0.07, green: 0.65, blue: 0.47)
        case .undefined:  return Color.secondary
        }
    }

    var label: String {
        switch self {
        case .toDo:       return "To Do"
        case .inProgress: return "In Progress"
        case .done:       return "Done"
        case .undefined:  return "Unknown"
        }
    }
}

// MARK: - Jira Ticket (flattened DTO)

struct JiraTicket: Identifiable, Hashable {
    let id: String         // issue key e.g. "PROJ-123"
    let summary: String
    let statusName: String
    let statusCategory: JiraStatusCategory
    let issueType: String
    let assignee: String?
    let priority: String?
}

// MARK: - Raw Decodable wrappers (nested JSON → flat DTO)

struct JiraSearchResponse: Decodable {
    let issues: [JiraIssueRaw]
    /// Nil when this is the last page.
    let nextPageToken: String?
}

struct JiraIssueRaw: Decodable {
    let key: String
    let fields: JiraFieldsRaw

    func toTicket() -> JiraTicket {
        JiraTicket(
            id: key,
            summary: fields.summary,
            statusName: fields.status.name,
            statusCategory: fields.status.statusCategory.name,
            issueType: fields.issuetype.name,
            assignee: fields.assignee?.displayName,
            priority: fields.priority?.name
        )
    }
}

struct JiraFieldsRaw: Decodable {
    let summary: String
    let status: JiraStatusRaw
    let issuetype: JiraIssueTypeRaw
    let assignee: JiraUserRaw?
    let priority: JiraPriorityRaw?
}

struct JiraStatusRaw: Decodable {
    let name: String
    let statusCategory: JiraStatusCategoryRaw
}

struct JiraStatusCategoryRaw: Decodable {
    let name: JiraStatusCategory
}

struct JiraIssueTypeRaw: Decodable {
    let name: String
}

struct JiraUserRaw: Decodable {
    let displayName: String
}

struct JiraPriorityRaw: Decodable {
    let name: String
}

// MARK: - Search Request Body

struct JiraSearchRequest: Encodable {
    let jql: String
    let maxResults: Int
    let fields: [String]
    /// Omit on the first page; include the token from the previous response for subsequent pages.
    let nextPageToken: String?

    init(jql: String, nextPageToken: String? = nil, maxResults: Int = 25) {
        self.jql = jql
        self.nextPageToken = nextPageToken
        self.maxResults = maxResults
        self.fields = ["summary", "status", "issuetype", "assignee", "priority"]
    }
}

// MARK: - Credentials (in-memory only; persisted via Keychain)

struct JiraCredentials {
    let subdomain: String
    let email: String
    let apiToken: String

    var baseURL: URL? {
        let trimmed = subdomain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "https://\(trimmed).atlassian.net")
    }

    func browseURL(for key: String) -> URL? {
        baseURL?.appendingPathComponent("browse/\(key)")
    }
}
