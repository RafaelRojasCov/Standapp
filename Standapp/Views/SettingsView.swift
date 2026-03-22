import SwiftUI

struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notificationManager = NotificationManager.shared

    // MARK: - Jira credential state (write-only fields; token never pre-filled)
    @State private var jiraSubdomain: String = ""
    @State private var jiraEmail: String = ""
    @State private var jiraApiToken: String = ""
    @State private var jiraCredentialsSaved: Bool = false

    private let keychain = KeychainManager.shared

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

                    // ── Jira API section ──────────────────────────────────────────
                    jiraSection

                    // ── Slack API section ──────────────────────────────────────────
                    slackSection

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
                }
                .padding(20)
                .contentShape(Rectangle())
                // Block tap-through to the dismiss layer
                .onTapGesture {}
            }
        }
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
            // Pre-fill subdomain and email if already saved; never pre-fill token.
            if let creds = try? keychain.loadJiraCredentials() {
                jiraSubdomain = creds.subdomain
                jiraEmail = creds.email
                jiraCredentialsSaved = true
            }
        }
    }

    // MARK: - Jira Section

    private var jiraSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Jira")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 16) {
                // Subdomain
                VStack(alignment: .leading, spacing: 6) {
                    Text("Subdomain")
                        .font(.headline)
                    HStack(spacing: 6) {
                        TextField("yourcompany", text: $jiraSubdomain)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        Text(".atlassian.net")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }

                Divider()

                // Email
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.headline)
                    TextField("you@company.com", text: $jiraEmail)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }

                Divider()

                // API Token
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Token")
                        .font(.headline)
                    SecureField(jiraCredentialsSaved ? "Token saved — enter new token to replace" : "Paste your API token", text: $jiraApiToken)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    Text("Generate at id.atlassian.com → Security → API tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Save / Remove row
                HStack {
                    if jiraCredentialsSaved {
                        Button("Remove", role: .destructive) {
                            keychain.deleteJiraCredentials()
                            jiraSubdomain = ""
                            jiraEmail = ""
                            jiraApiToken = ""
                            jiraCredentialsSaved = false
                        }
                        .foregroundStyle(.red)
                    }
                    Spacer()
                    if jiraCredentialsSaved {
                        Label("Saved in Keychain", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Button("Save to Keychain") {
                        let tokenToSave = jiraApiToken.isEmpty
                            ? (try? keychain.loadJiraCredentials())?.apiToken ?? ""
                            : jiraApiToken
                        let creds = JiraCredentials(
                            subdomain: jiraSubdomain,
                            email: jiraEmail,
                            apiToken: tokenToSave
                        )
                        try? keychain.saveJiraCredentials(creds)
                        jiraApiToken = ""
                        jiraCredentialsSaved = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(jiraSubdomain.isEmpty || jiraEmail.isEmpty || (!jiraCredentialsSaved && jiraApiToken.isEmpty))
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }

    // MARK: - Slack Section

    private var slackSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Slack")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            SlackPreferencesView()
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
