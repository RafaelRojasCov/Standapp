import SwiftUI

@main
struct StandappApp: App {

    @State private var settings = AppSettings()

    init() {
        // Touch the shared instance early so the UNUserNotificationCenterDelegate
        // is registered before any pending notification response is delivered.
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
