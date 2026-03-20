import SwiftUI

struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notificationManager = NotificationManager.shared

    /// Weekday labels (index 0 = Sunday, 1 = Monday … 6 = Saturday)
    private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        @Bindable var settings = settings
        Form {
            // ── Integrations ──────────────────────────────────────────────────
            Section {
                LabeledContent("JIRA Base URL") {
                    TextField(
                        "https://company.atlassian.net",
                        text: $settings.jiraBaseUrl
                    )
                    .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Slack Channel URI") {
                    TextField(
                        "slack://channel?team=T123&id=C123",
                        text: $settings.slackChannelUri
                    )
                    .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Integrations")
                    .font(.headline)
                    .padding(.bottom, 2)
            }

            // ── Scheduler ─────────────────────────────────────────────────────
            Section {
                LabeledContent("Time") {
                    HStack(spacing: 6) {
                        Picker("Hour", selection: $settings.scheduledHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .frame(width: 70)
                        .labelsHidden()

                        Text(":")
                            .font(.body.bold())

                        Picker("Minute", selection: $settings.scheduledMinute) {
                            ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .frame(width: 70)
                        .labelsHidden()
                    }
                }

                LabeledContent("Days") {
                    HStack(spacing: 6) {
                        // Weekday 1 = Sunday … 7 = Saturday (Calendar convention)
                        ForEach(1...7, id: \.self) { day in
                            let label   = weekdayLabels[day - 1]
                            let enabled = settings.scheduledWeekdays.contains(day)
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
                Text("A local notification will appear at the selected time on selected days.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // ── Actions ───────────────────────────────────────────────────────
            if notificationManager.authorizationStatus == .denied {
                Label("Notifications are disabled in System Settings. Scheduled reminders will not appear.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Request Notification Permission") {
                    notificationManager.requestAuthorization()
                }

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
