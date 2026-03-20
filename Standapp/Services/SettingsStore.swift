import Foundation

/// Persists and restores all AppSettings via UserDefaults.
final class SettingsStore {

    static let shared = SettingsStore()
    private init() {}

    private let defaults = UserDefaults.standard
    private let settingsKey = "com.standapp.settings"

    // MARK: - Codable snapshot

    private struct Snapshot: Codable {
        var profiles: [StandupProfile]
        var yesterdayItems: [StandupItem]
        var todayItems: [StandupItem]
        var blockerState: BlockerState
        var blockersItems: [StandupItem]

        private enum CodingKeys: String, CodingKey {
            case profiles
            case yesterdayItems
            case todayItems
            case blockerState
            case blockersItems
            case jiraBaseUrl
            case slackChannelUri
            case scheduledWeekdays
            case scheduledHour
            case scheduledMinute
            case hasBlockers
        }

        init(
            profiles: [StandupProfile],
            yesterdayItems: [StandupItem],
            todayItems: [StandupItem],
            blockerState: BlockerState,
            blockersItems: [StandupItem]
        ) {
            self.profiles = profiles
            self.yesterdayItems = yesterdayItems
            self.todayItems = todayItems
            self.blockerState = blockerState
            self.blockersItems = blockersItems
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let decodedProfiles = try container.decodeIfPresent([StandupProfile].self, forKey: .profiles),
               !decodedProfiles.isEmpty {
                profiles = decodedProfiles
            } else {
                let jiraBaseUrl = try container.decodeIfPresent(String.self, forKey: .jiraBaseUrl) ?? ""
                let slackChannelUri = try container.decodeIfPresent(String.self, forKey: .slackChannelUri) ?? ""
                let scheduledWeekdays = try container.decodeIfPresent([Int].self, forKey: .scheduledWeekdays) ?? [2, 3, 4, 5, 6]
                let scheduledHour = try container.decodeIfPresent(Int.self, forKey: .scheduledHour) ?? 9
                let scheduledMinute = try container.decodeIfPresent(Int.self, forKey: .scheduledMinute) ?? 0
                profiles = [StandupProfile(
                    name: "Default",
                    jiraBaseUrl: jiraBaseUrl,
                    slackChannelUri: slackChannelUri,
                    scheduledWeekdays: scheduledWeekdays,
                    scheduledHour: scheduledHour,
                    scheduledMinute: scheduledMinute
                )]
            }

            yesterdayItems = try container.decodeIfPresent([StandupItem].self, forKey: .yesterdayItems) ?? [StandupItem()]
            todayItems = try container.decodeIfPresent([StandupItem].self, forKey: .todayItems) ?? [StandupItem()]
            blockersItems = try container.decodeIfPresent([StandupItem].self, forKey: .blockersItems) ?? [StandupItem()]

            if let decodedState = try container.decodeIfPresent(BlockerState.self, forKey: .blockerState) {
                blockerState = decodedState
            } else if let legacyHasBlockers = try container.decodeIfPresent(Bool.self, forKey: .hasBlockers) {
                blockerState = legacyHasBlockers ? .hasBlockers : .noBlockers
            } else {
                blockerState = .unanswered
            }
        }
    }

    // MARK: - Public API

    func save(_ settings: AppSettings) {
        guard !settings.isLoading else { return }
        var profiles = settings.profiles
        if profiles.isEmpty {
            profiles = [StandupProfile()]
        }
        profiles[0].jiraBaseUrl = settings.jiraBaseUrl
        profiles[0].slackChannelUri = settings.slackChannelUri
        profiles[0].scheduledWeekdays = Array(settings.scheduledWeekdays)
        profiles[0].scheduledHour = settings.scheduledHour
        profiles[0].scheduledMinute = settings.scheduledMinute
        let snapshot = Snapshot(
            profiles: profiles,
            yesterdayItems: settings.yesterdayItems,
            todayItems: settings.todayItems,
            blockerState: settings.blockerState,
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
        let profile = snapshot.profiles.first ?? StandupProfile()
        settings.profiles = snapshot.profiles.isEmpty ? [profile] : snapshot.profiles
        settings.jiraBaseUrl = profile.jiraBaseUrl
        settings.slackChannelUri = profile.slackChannelUri
        settings.scheduledWeekdays = Set(profile.scheduledWeekdays)
        settings.scheduledHour = profile.scheduledHour
        settings.scheduledMinute = profile.scheduledMinute
        settings.yesterdayItems     = snapshot.yesterdayItems
        settings.todayItems         = snapshot.todayItems
        settings.blockerState       = snapshot.blockerState
        settings.blockersItems      = snapshot.blockersItems
        settings.isLoading          = false
    }
}
