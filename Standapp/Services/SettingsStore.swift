import Foundation

/// Persists and restores all AppSettings via UserDefaults.
final class SettingsStore {

    static let shared = SettingsStore()
    private init() {}

    private let defaults = UserDefaults.standard
    private let settingsKey = "com.standapp.settings"

    // MARK: - Codable snapshot

    private struct Snapshot: Codable {
        var jiraBaseUrl: String
        var slackChannelUri: String
        var scheduledWeekdays: [Int]
        var scheduledHour: Int
        var scheduledMinute: Int
        var yesterdayItems: [StandupItem]
        var todayItems: [StandupItem]
        var hasBlockers: Bool
        var blockersItems: [StandupItem]
    }

    // MARK: - Public API

    func save(_ settings: AppSettings) {
        guard !settings.isLoading else { return }
        let snapshot = Snapshot(
            jiraBaseUrl: settings.jiraBaseUrl,
            slackChannelUri: settings.slackChannelUri,
            scheduledWeekdays: Array(settings.scheduledWeekdays),
            scheduledHour: settings.scheduledHour,
            scheduledMinute: settings.scheduledMinute,
            yesterdayItems: settings.yesterdayItems,
            todayItems: settings.todayItems,
            hasBlockers: settings.hasBlockers,
            blockersItems: settings.blockersItems
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    func load(into settings: AppSettings) {
        guard
            let data = defaults.data(forKey: settingsKey),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }

        settings.isLoading          = true
        settings.jiraBaseUrl        = snapshot.jiraBaseUrl
        settings.slackChannelUri    = snapshot.slackChannelUri
        settings.scheduledWeekdays  = Set(snapshot.scheduledWeekdays)
        settings.scheduledHour      = snapshot.scheduledHour
        settings.scheduledMinute    = snapshot.scheduledMinute
        settings.yesterdayItems     = snapshot.yesterdayItems
        settings.todayItems         = snapshot.todayItems
        settings.hasBlockers        = snapshot.hasBlockers
        settings.blockersItems      = snapshot.blockersItems
        settings.isLoading          = false
    }
}
