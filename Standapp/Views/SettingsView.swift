import SwiftUI

struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var jiraEmail: String = ""
    @State private var jiraAPIToken: String = ""
    @State private var credentialError: String?

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

        ZStack {
            // Tap outside to dismiss
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            // Modal content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Header with close button ───────────────────────────────────
                    HStack(alignment: .top) {
                        Text("Integraciones")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color(NSColor.darkGray).opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // ── Integrations section ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 16) {
                        // Jira Subdomain
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Jira Subdomain")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            TextField("", text: $bindableSettings.jiraSubdomain, prompt: Text("company"))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            Text("Only subdomain, without https:// or .atlassian.net")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // JIRA Base URL
                        VStack(alignment: .leading, spacing: 8) {
                            Text("JIRA Base URL")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            TextField("", text: $bindableSettings.jiraBaseUrl, prompt: Text("https://company.atlassian.net"))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            Text("Example: https://company.atlassian.net")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Jira Credentials (Keychain)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Jira Email")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            TextField("", text: $jiraEmail, prompt: Text("name@company.com"))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Jira API Token")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            SecureField("", text: $jiraAPIToken, prompt: Text("Stored securely in Keychain"))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }

                        // Slack Channel URL
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Slack Channel URL")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            TextField("", text: $bindableSettings.slackChannelUri, prompt: Text("slack://channel?team=T123&id=C123"))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            Text("Example: slack://channel?team=T123&id=C123")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // ── Reminder Schedule section ──────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Reminder Schedule")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .padding(.bottom, 12)

                        VStack(alignment: .leading, spacing: 0) {
                            // Time picker
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Time")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
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
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(16)

                            Divider()
                                .padding(.horizontal, 16)

                            // Days picker
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Days")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 4) {
                                    ForEach(1...7, id: \.self) { day in
                                        let label   = weekdayLabels[day - 1]
                                        let enabled = bindableSettings.scheduledWeekdays.contains(day)
                                        Button {
                                            toggleWeekday(day)
                                        } label: {
                                            Text(label)
                                                .font(.system(size: 12, weight: enabled ? .semibold : .regular))
                                                .foregroundStyle(enabled ? .white : Color.secondary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 6)
                                                .background(enabled ? Color.accentColor : Color.clear)
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                        .help(enabled ? "Enabled" : "Disabled")
                                    }
                                }
                            }
                            .padding(16)
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)

                        Text("Aparecerá una notificación local a la hora seleccionada y en los días elegidos.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    // ── Actions ────────────────────────────────────────────────────
                    if notificationManager.authorizationStatus == .denied {
                        Label("Notifications are disabled in System Settings. Scheduled reminders will not appear.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    if hasGrantedNotificationPermission {
                        Label("Permissions granted.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    if let credentialError {
                        Label(credentialError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    HStack {
                        Spacer()
                        Button(requestPermissionButtonTitle) {
                            notificationManager.requestAuthorization()
                        }
                        .disabled(hasGrantedNotificationPermission)

                        Button("Save & Schedule") {
                            do {
                                let email = jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                                let token = jiraAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
                                if email.isEmpty && token.isEmpty {
                                    credentialError = nil
                                } else if email.isEmpty || token.isEmpty {
                                    credentialError = "Jira email and API token are required."
                                    return
                                } else {
                                    try KeychainManager.shared.save(key: "jira.email", value: email)
                                    try KeychainManager.shared.save(key: "jira.apiToken", value: token)
                                    credentialError = nil
                                }
                            } catch {
                                credentialError = "Unable to save Jira credentials in Keychain."
                                return
                            }
                            notificationManager.reschedule(with: settings)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .padding(20)
                .contentShape(Rectangle())
                // Block tap-through to the dismiss layer
                .onTapGesture {}
            }
        }
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
            jiraEmail = (try? KeychainManager.shared.retrieve(key: "jira.email")) ?? ""
            jiraAPIToken = (try? KeychainManager.shared.retrieve(key: "jira.apiToken")) ?? ""
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
        .frame(width: 460, height: 520)
}
