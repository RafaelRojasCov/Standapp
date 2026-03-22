import Foundation

/// A ticket selected from Jira, carrying its key and status for preview formatting.
struct SelectedTicket: Identifiable, Codable, Equatable, Hashable {
    var id: String      // e.g. "DEV-101"
    var statusName: String = ""
    var statusCategory: String = ""   // raw string so it stays Codable without importing JiraModels

    init(id: String, statusName: String = "", statusCategory: String = "") {
        self.id = id
        self.statusName = statusName
        self.statusCategory = statusCategory
    }

    /// Convenience init from a plain ticket key typed manually.
    init(key: String) {
        self.id = key
        self.statusName = ""
        self.statusCategory = ""
    }
}

/// A single entry in a standup section: one description paired with zero or more ticket IDs.
struct StandupItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String = ""
    /// Ordered list of selected tickets. May be empty, or contain manually-typed keys
    /// (statusName will be empty in that case).
    var tickets: [SelectedTicket] = []

    // MARK: - Codable with backwards-compat for legacy `ticketId: String`

    private enum CodingKeys: String, CodingKey {
        case id, text, tickets, ticketId
    }

    init(id: UUID = UUID(), text: String = "", tickets: [SelectedTicket] = []) {
        self.id = id
        self.text = text
        self.tickets = tickets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id     = try c.decodeIfPresent(UUID.self,   forKey: .id)   ?? UUID()
        text   = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        if let savedTickets = try c.decodeIfPresent([SelectedTicket].self, forKey: .tickets) {
            tickets = savedTickets
        } else if let legacyId = try c.decodeIfPresent(String.self, forKey: .ticketId),
                  !legacyId.trimmingCharacters(in: .whitespaces).isEmpty {
            // Migrate single string → array
            tickets = [SelectedTicket(key: legacyId)]
        } else {
            tickets = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,      forKey: .id)
        try c.encode(text,    forKey: .text)
        try c.encode(tickets, forKey: .tickets)
    }
}
