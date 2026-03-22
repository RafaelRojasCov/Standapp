import Foundation
import OSLog

protocol AuthenticationProvider {
    func authenticate(_ request: inout URLRequest) async throws
}

struct BasicAuthenticationProvider: AuthenticationProvider {
    let keychain: KeychainManager

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    func authenticate(_ request: inout URLRequest) async throws {
        let email = try keychain.retrieve(key: "jira.email").trimmingCharacters(in: .whitespacesAndNewlines)
        let token = try keychain.retrieve(key: "jira.apiToken").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !token.isEmpty else {
            throw JiraError.invalidCredentials
        }
        let credentials = "\(email):\(token)"
        guard let encoded = credentials.data(using: .utf8)?.base64EncodedString() else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
    }
}

enum JiraError: LocalizedError {
    case invalidBaseURL
    case invalidCredentials
    case keychainUnavailable
    case rateLimited(retryAfter: Int)
    case unauthorized
    case serverError(statusCode: Int)
    case transport(URLError)
    case decoding
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid Atlassian domain. Please verify your subdomain in Settings."
        case .invalidCredentials, .keychainUnavailable:
            return "Jira credentials are missing. Please configure email and API token in Settings."
        case .rateLimited(let retryAfter):
            return "Jira rate limit reached. Please retry in \(retryAfter) seconds."
        case .unauthorized:
            return "Jira authentication failed. Verify your email and API token."
        case .serverError(let statusCode):
            return "Jira request failed with status code \(statusCode)."
        case .transport(let error):
            return error.localizedDescription
        case .decoding:
            return "Unable to process Jira response."
        case .unknown:
            return "Unexpected Jira error."
        }
    }
}

struct JiraAPIService {
    private let authenticationProvider: AuthenticationProvider
    private let session: URLSession
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.standapp.Standapp", category: "Networking")
    private let maxRetryAfterSeconds = 10

    init(authenticationProvider: AuthenticationProvider = BasicAuthenticationProvider(), session: URLSession = .shared) {
        self.authenticationProvider = authenticationProvider
        self.session = session
    }

    func searchTickets(subdomain: String, jql: String, startAt: Int, maxResults: Int = 50) async throws -> JiraSearchResponse {
        let normalized = subdomain.jiraNormalizedSubdomain
        guard !normalized.isEmpty,
              let url = URL(string: "https://\(normalized).atlassian.net/rest/api/3/search") else {
            throw JiraError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            try await authenticationProvider.authenticate(&request)
        } catch is KeychainError {
            throw JiraError.keychainUnavailable
        } catch {
            throw JiraError.invalidCredentials
        }

        let payload = JiraSearchPayload(
            jql: jql,
            startAt: startAt,
            maxResults: maxResults,
            fields: ["summary", "status", "assignee"]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let maxAttempts = 2
        var attempts = 0

        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw JiraError.unknown
                }

                switch httpResponse.statusCode {
                case 200:
                    do {
                        return try JSONDecoder().decode(JiraSearchResponse.self, from: data)
                    } catch {
                        throw JiraError.decoding
                    }
                case 401:
                    throw JiraError.unauthorized
                case 429:
                    let rawRetryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1
                    let retryAfter = min(max(rawRetryAfter, 1), maxRetryAfterSeconds)
                    let cappedFromMessage = rawRetryAfter > maxRetryAfterSeconds ? " (capped from \(rawRetryAfter))" : ""
                    logger.error("Jira rate limit reached. retry_after=\(retryAfter)\(cappedFromMessage)")
                    if attempts < maxAttempts {
                        attempts += 1
                        try await Task.sleep(for: .seconds(Double(retryAfter)))
                        continue
                    }
                    throw JiraError.rateLimited(retryAfter: retryAfter)
                default:
                    logger.error("Jira request failed with status code \(httpResponse.statusCode)")
                    throw JiraError.serverError(statusCode: httpResponse.statusCode)
                }
            } catch let error as URLError {
                throw JiraError.transport(error)
            } catch let error as JiraError {
                throw error
            } catch {
                throw JiraError.unknown
            }
        }
    }
}

private struct JiraSearchPayload: Encodable {
    let jql: String
    let startAt: Int
    let maxResults: Int
    let fields: [String]
}
