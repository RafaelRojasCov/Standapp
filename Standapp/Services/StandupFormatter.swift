import Foundation

/// Formats a standup draft into a clean Markdown string suitable for Slack.
struct StandupFormatter {

    let settings: AppSettings

    // MARK: - Public

    func format() -> String {
        var lines: [String] = []

        lines.append("**Yesterday**")
        lines.append(contentsOf: formatItems(settings.yesterdayItems))

        lines.append("")
        lines.append("**Today**")
        lines.append(contentsOf: formatItems(settings.todayItems))

        lines.append("")
        lines.append("**Blockers**")
        if settings.blockerState == .hasBlockers {
            lines.append(contentsOf: formatItems(settings.blockersItems))
        } else {
            lines.append("• No blockers")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func formatItems(_ items: [StandupItem]) -> [String] {
        items.compactMap { item in
            let trimmedText   = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTicket = item.ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return nil }

            if trimmedTicket.isEmpty {
                return "• \(trimmedText)"
            }

            let ticketLink = makeTicketLink(trimmedTicket)
            return "• \(trimmedText) \(ticketLink)"
        }
    }

    private func makeTicketLink(_ ticketId: String) -> String {
        let base = settings.jiraBaseUrl
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let safeLabel = sanitizeSlackLabel(ticketId)

        if base.isEmpty {
            return "(\(safeLabel))"
        }
        guard let baseURL = URL(string: "\(base)/") else {
            return "(\(safeLabel))"
        }
        let url = baseURL
            .appendingPathComponent("browse")
            .appendingPathComponent(ticketId)
            .absoluteString
        return "[\(safeLabel)](\(url))"
    }

    private func sanitizeSlackLabel(_ text: String) -> String {
        // Slack uses `<url|label>` markup; these replacements prevent label text
        // from breaking the delimiter syntax when users type reserved characters.
        text
            .replacingOccurrences(of: "|", with: "¦")
            .replacingOccurrences(of: "<", with: "‹")
            .replacingOccurrences(of: ">", with: "›")
    }
}
