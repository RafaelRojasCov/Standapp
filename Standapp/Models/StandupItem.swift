import Foundation

/// A single entry in a standup section, pairing a description with an optional ticket ID.
struct StandupItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String = ""
    var ticketId: String = ""
}
