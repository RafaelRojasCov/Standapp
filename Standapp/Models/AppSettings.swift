import Foundation
import Observation

struct StandupProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = "Default"
    var jiraBaseUrl: String = ""
    var slackChannelUri: String = ""
    var scheduledWeekdays: [Int] = [2, 3, 4, 5, 6]
    var scheduledHour: Int = 9
    var scheduledMinute: Int = 0
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
