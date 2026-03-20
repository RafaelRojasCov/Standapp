import AppKit
import Combine
import Foundation
import UserNotifications

/// Schedules repeating local notifications at the configured time / weekdays
/// and re-focuses the app window when the user clicks them.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    private let categoryID   = "STANDUP_REMINDER"
    private let identifierBase = "com.standapp.reminder"
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Public API

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            _ = granted
            _ = error
            DispatchQueue.main.async {
                self.refreshAuthorizationStatus()
            }
        }
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    /// Cancels all pending reminders and schedules new ones based on `settings`.
    func reschedule(with settings: AppSettings) {
        let center   = UNUserNotificationCenter.current()
        let weekdays = settings.scheduledWeekdays
        let hour     = settings.scheduledHour
        let minute   = settings.scheduledMinute

        // Remove existing reminders first, then schedule new ones inside the
        // callback so the two operations are properly serialised and the newly
        // added requests are never accidentally removed.
        center.getPendingNotificationRequests { requests in

            let ids = requests
                .filter { $0.identifier.hasPrefix(self.identifierBase) }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: ids)

            // Schedule one notification per enabled weekday.
            for weekday in weekdays {
                self.scheduleNotification(weekday: weekday, hour: hour, minute: minute)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Bring the app to the front and make sure the main window is visible.
        // Must run on the main thread because AppKit UI calls require it.
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first(where: { $0.canBecomeMain })?
                .makeKeyAndOrderFront(nil)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Private

    private func scheduleNotification(weekday: Int, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Standup Time! 🚀"
        content.body  = "Time to fill in today's standup."
        content.sound = .default
        content.categoryIdentifier = categoryID

        var components        = DateComponents()
        components.weekday    = weekday
        components.hour       = hour
        components.minute     = minute
        components.second     = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let id      = "\(identifierBase).\(weekday)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationManager] Failed to schedule weekday \(weekday): \(error)")
            }
        }
    }
}
