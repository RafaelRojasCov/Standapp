import SwiftUI

struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notificationManager = NotificationManager.shared

    /// Weekday labels (index 0 = Sunday, 1 = Monday … 6 = Saturday)
    private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private var hasGrantedNotificationPermission: Bool {
        notificationManager.authorizationStatus == .authorized || notificationManager.authorizationStatus == .provisional
    }

    private var requestPermissionButtonTitle: String {
        if hasGrantedNotificationPermission {
            return "Permissions granted"
        }
        return notificationManager.authorizationStatus == .notDetermined ? "Request Permissions" : "Re-check Permissions"
    }

    var body: some View {
        @Bindable var bindableSettings = settings
        Form {
            // ── Integrations ──────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("JIRA Base URL")
                        .font(.headline)
                    TextField(
                        text: $bindableSettings.jiraBaseUrl,
                        prompt: Text("https://company.atlassian.net")
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    Text("Example: https://company.atlassian.net")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Slack Channel URI")
                        .font(.headline)
                    TextField(
                        text: $bindableSettings.slackChannelUri,
                        prompt: Text("slack://channel?team=T123&id=C123")
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    Text("Example: slack://channel?team=T123&id=C123")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("Integrations")
                    .font(.headline)
                    .padding(.bottom, 2)
            }

            // ── Scheduler ─────────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Time")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Picker("Hour", selection: $bindableSettings.scheduledHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .frame(width: 70)
                        .labelsHidden()

                        Text(":")
                            .font(.body.bold())

                        Picker("Minute", selection: $bindableSettings.scheduledMinute) {
                            ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .frame(width: 70)
                        .labelsHidden()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Days")
                        .font(.headline)
                    HStack(spacing: 6) {
                        // Weekday 1 = Sunday … 7 = Saturday (Calendar convention)
                        ForEach(1...7, id: \.self) { day in
                            let label   = weekdayLabels[day - 1]
                            let enabled = bindableSettings.scheduledWeekdays.contains(day)
                            Button(label) {
                                toggleWeekday(day)
                            }
                            .buttonStyle(.bordered)
                            .tint(enabled ? .accentColor : .secondary)
                            .opacity(enabled ? 1.0 : 0.4)
                            .help(enabled ? "Enabled" : "Disabled")
                        }
                    }
                }
            } header: {
                Text("Reminder Schedule")
                    .font(.headline)
                    .padding(.bottom, 2)
            } footer: {
                Text("Aparecerá una notificación local a la hora seleccionada en los días elegidos.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // ── Actions ───────────────────────────────────────────────────────
            if notificationManager.authorizationStatus == .denied {
                Label("Notifications are disabled in System Settings. Scheduled reminders will not appear.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            if hasGrantedNotificationPermission {
                Label("Permissions granted.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            HStack {
                Spacer()
                Button(requestPermissionButtonTitle) {
                    notificationManager.requestAuthorization()
                }
                .disabled(hasGrantedNotificationPermission)

                Button("Save & Schedule") {
                    notificationManager.reschedule(with: settings)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 8)
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle("Settings")
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
        }
    }

    // MARK: -

    private func toggleWeekday(_ day: Int) {
        if settings.scheduledWeekdays.contains(day) {
            // Keep at least one day enabled.
            if settings.scheduledWeekdays.count > 1 {
                settings.scheduledWeekdays.remove(day)
            }
        } else {
            settings.scheduledWeekdays.insert(day)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
        .frame(width: 460, height: 420)
}
