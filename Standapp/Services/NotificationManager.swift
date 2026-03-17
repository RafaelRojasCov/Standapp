import AppKit
import Foundation
import UserNotifications

/// Schedules repeating local notifications at the configured time / weekdays
/// and re-focuses the app window when the user clicks them.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    private let categoryID   = "STANDUP_REMINDER"
    private let identifierBase = "com.standapp.reminder"

    // MARK: - Public API

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                // Nothing extra needed — scheduling happens separately.
            }
        }
    }

    /// Cancels all pending reminders and schedules new ones based on `settings`.
    func reschedule(with settings: AppSettings) {
        let center = UNUserNotificationCenter.current()

        // Remove all previously scheduled reminders.
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix(self.identifierBase) }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }

        // Schedule one notification per enabled weekday.
        for weekday in settings.scheduledWeekdays {
            scheduleNotification(
                weekday: weekday,
                hour: settings.scheduledHour,
                minute: settings.scheduledMinute
            )
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Bring the app to the front.
        NSApplication.shared.activate(ignoringOtherApps: true)
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

        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
