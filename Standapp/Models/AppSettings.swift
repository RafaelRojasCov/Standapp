import Foundation

/// Central observable state for the entire app: settings + today's standup draft.
class AppSettings: ObservableObject {

    /// Set to `true` during bulk-load operations to suppress redundant saves.
    var isLoading = false

    // MARK: - Persisted settings
    @Published var jiraBaseUrl: String = "" {
        didSet { SettingsStore.shared.save(self) }
    }
    @Published var slackChannelUri: String = "" {
        didSet { SettingsStore.shared.save(self) }
    }
    /// Weekday indices using Calendar convention: 1 = Sunday, 2 = Monday … 7 = Saturday.
    /// Default is `[2, 3, 4, 5, 6]` (Monday–Friday).
    @Published var scheduledWeekdays: Set<Int> = [2, 3, 4, 5, 6] {
        didSet { SettingsStore.shared.save(self) }
    }
    @Published var scheduledHour: Int = 9 {
        didSet { SettingsStore.shared.save(self) }
    }
    @Published var scheduledMinute: Int = 0 {
        didSet { SettingsStore.shared.save(self) }
    }

    // MARK: - Today's standup draft
    @Published var yesterdayItems: [StandupItem] = [StandupItem()] {
        didSet { SettingsStore.shared.save(self) }
    }
    @Published var todayItems: [StandupItem] = [StandupItem()] {
        didSet { SettingsStore.shared.save(self) }
    }
    @Published var hasBlockers: Bool = false {
        didSet { SettingsStore.shared.save(self) }
    }
    @Published var blockersItems: [StandupItem] = [StandupItem()] {
        didSet { SettingsStore.shared.save(self) }
    }

    init() {
        SettingsStore.shared.load(into: self)
    }
}
