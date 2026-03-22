import Foundation
import Observation

struct StandupProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = "Default"
    var jiraSubdomain: String = ""
    var jiraBaseUrl: String = ""
    var slackChannelUri: String = ""
    var scheduledWeekdays: [Int] = [2, 3, 4, 5, 6]
    var scheduledHour: Int = 9
    var scheduledMinute: Int = 0

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case jiraSubdomain
        case jiraBaseUrl
        case slackChannelUri
        case scheduledWeekdays
        case scheduledHour
        case scheduledMinute
    }

    init() {}

    init(
        id: UUID = UUID(),
        name: String = "Default",
        jiraSubdomain: String = "",
        jiraBaseUrl: String = "",
        slackChannelUri: String = "",
        scheduledWeekdays: [Int] = [2, 3, 4, 5, 6],
        scheduledHour: Int = 9,
        scheduledMinute: Int = 0
    ) {
        self.id = id
        self.name = name
        self.jiraSubdomain = jiraSubdomain
        self.jiraBaseUrl = jiraBaseUrl
        self.slackChannelUri = slackChannelUri
        self.scheduledWeekdays = scheduledWeekdays
        self.scheduledHour = scheduledHour
        self.scheduledMinute = scheduledMinute
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Default"
        jiraSubdomain = try container.decodeIfPresent(String.self, forKey: .jiraSubdomain) ?? ""
        jiraBaseUrl = try container.decodeIfPresent(String.self, forKey: .jiraBaseUrl) ?? ""
        slackChannelUri = try container.decodeIfPresent(String.self, forKey: .slackChannelUri) ?? ""
        scheduledWeekdays = try container.decodeIfPresent([Int].self, forKey: .scheduledWeekdays) ?? [2, 3, 4, 5, 6]
        scheduledHour = try container.decodeIfPresent(Int.self, forKey: .scheduledHour) ?? 9
        scheduledMinute = try container.decodeIfPresent(Int.self, forKey: .scheduledMinute) ?? 0
    }
}

enum BlockerState: String, Codable, CaseIterable {
    case unanswered
    case noBlockers
    case hasBlockers
}

/// Central observable state for the entire app: settings + today's standup draft.
@Observable
final class AppSettings {

    /// Set to `true` during bulk-load operations to suppress redundant saves.
    var isLoading = false

    // MARK: - Persisted settings
    var jiraBaseUrl: String = "" {
        didSet { SettingsStore.shared.save(self) }
    }
    var jiraSubdomain: String = "" {
        didSet { SettingsStore.shared.save(self) }
    }
    var slackChannelUri: String = "" {
        didSet { SettingsStore.shared.save(self) }
    }
    /// Weekday indices using Calendar convention: 1 = Sunday, 2 = Monday … 7 = Saturday.
    /// Default is `[2, 3, 4, 5, 6]` (Monday–Friday).
    var scheduledWeekdays: Set<Int> = [2, 3, 4, 5, 6] {
        didSet { SettingsStore.shared.save(self) }
    }
    var scheduledHour: Int = 9 {
        didSet { SettingsStore.shared.save(self) }
    }
    var scheduledMinute: Int = 0 {
        didSet { SettingsStore.shared.save(self) }
    }
    var profiles: [StandupProfile] = [StandupProfile()] {
        didSet { SettingsStore.shared.save(self) }
    }

    // MARK: - Today's standup draft
    var yesterdayItems: [StandupItem] = [StandupItem()] {
        didSet { SettingsStore.shared.save(self) }
    }
    var todayItems: [StandupItem] = [StandupItem()] {
        didSet { SettingsStore.shared.save(self) }
    }
    var blockerState: BlockerState = .noBlockers {
        didSet { SettingsStore.shared.save(self) }
    }
    var blockersItems: [StandupItem] = [StandupItem()] {
        didSet { SettingsStore.shared.save(self) }
    }

    init() {
        SettingsStore.shared.load(into: self)
    }
}
