import Foundation
import OSLog

// MARK: - Authentication Provider Protocol

protocol AuthenticationProvider: Sendable {
    /// Injects authentication headers into the given URLRequest.
    func authenticate(_ request: inout URLRequest) throws
}

// MARK: - Basic Auth Provider

struct BasicAuthenticationProvider: AuthenticationProvider {

    private let keychain: KeychainManager

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    func authenticate(_ request: inout URLRequest) throws {
        let credentials = try keychain.loadJiraCredentials()
        let raw = "\(credentials.email):\(credentials.apiToken)"
        guard let data = raw.data(using: .utf8) else {
            throw JiraError.authFailed
        }
        request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
    }
}

// MARK: - Jira Network Service Protocol

protocol JiraNetworkServiceProtocol: Sendable {
    func search(jql: String, nextPageToken: String?, maxResults: Int) async throws -> JiraSearchResponse
}

// MARK: - Jira Network Service Implementation

final class JiraNetworkService: JiraNetworkServiceProtocol, @unchecked Sendable {

    private let authProvider: any AuthenticationProvider
    private let keychain: KeychainManager
    private let session: URLSession
    private let logger = Logger(subsystem: "com.standapp", category: "JiraNetwork")

    private let maxBackoffAttempts = 4
    private let requestTimeout: TimeInterval = 15

    init(
        authProvider: any AuthenticationProvider = BasicAuthenticationProvider(),
        keychain: KeychainManager = .shared,
        session: URLSession = .shared
    ) {
        self.authProvider = authProvider
        self.keychain = keychain
        self.session = session
    }

    // MARK: - Public API

    func search(jql: String, nextPageToken: String? = nil, maxResults: Int = 25) async throws -> JiraSearchResponse {
        let credentials = try keychain.loadJiraCredentials()

        guard let baseURL = credentials.baseURL else {
            throw JiraError.invalidSubdomain
        }

        let endpoint = baseURL.appendingPathComponent("rest/api/3/search/jql")
        let body = JiraSearchRequest(jql: jql, nextPageToken: nextPageToken, maxResults: maxResults)

        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        try authProvider.authenticate(&request)

        let tokenLabel = nextPageToken ?? "first page"
        logger.debug("POST \(endpoint.absoluteString) jql='\(jql)' page='\(tokenLabel)'")

        return try await performWithBackoff(request: request)
    }

    // MARK: - Backoff Logic

    private func performWithBackoff(request: URLRequest, attempt: Int = 0) async throws -> JiraSearchResponse {
        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw JiraError.invalidResponse(statusCode: -1)
            }

            switch http.statusCode {
            case 200:
                do {
                    return try JSONDecoder().decode(JiraSearchResponse.self, from: data)
                } catch {
                    throw JiraError.decodingFailed(underlying: error)
                }

            case 401, 403:
                logger.warning("Jira auth error: HTTP \(http.statusCode)")
                throw JiraError.authFailed

            case 429:
                let retryAfter = retryAfterInterval(from: http, attempt: attempt)
                logger.warning("Rate limited. Retry after \(retryAfter)s (attempt \(attempt))")

                guard attempt < maxBackoffAttempts else {
                    throw JiraError.rateLimited(retryAfter: retryAfter)
                }

                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                return try await performWithBackoff(request: request, attempt: attempt + 1)

            default:
                logger.error("Unexpected HTTP \(http.statusCode)")
                throw JiraError.invalidResponse(statusCode: http.statusCode)
            }

        } catch let error as URLError where error.code == .timedOut {
            throw JiraError.networkTimeout
        } catch let jiraError as JiraError {
            throw jiraError
        } catch {
            throw error
        }
    }

    /// Parses `Retry-After` header or falls back to exponential backoff.
    private func retryAfterInterval(from response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(header) {
            return seconds
        }
        // Exponential backoff: 1s, 2s, 4s, 8s
        return pow(2.0, Double(attempt))
    }
}
