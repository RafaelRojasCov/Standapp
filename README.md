# Standapp — macOS Daily Standup Assistant

A native macOS application (SwiftUI, macOS 14+) that streamlines daily standup reporting by formatting your answers and JIRA ticket links into clean Markdown for Slack.

### Home screen
<img width="1207" height="852" alt="image" src="https://github.com/user-attachments/assets/b5f99688-c56a-4240-ace2-7ebb6b8efa31" />

### Settings
<img width="1207" height="864" alt="image" src="https://github.com/user-attachments/assets/544f09f0-799c-4a68-96e0-70a3d3331028" />

### Jira Ticket Search
<img width="1207" height="852" alt="image" src="https://github.com/user-attachments/assets/e218c735-f68f-47b7-abe1-7c89be836db9" />

### Send message to slack channel
<img width="1207" height="852" alt="image" src="https://github.com/user-attachments/assets/288fa79f-a7b2-48e4-8f78-1d53403e94d6" />

### Send message to a Thread in a Channel
<img width="1207" height="852" alt="image" src="https://github.com/user-attachments/assets/3735e38a-091d-4d8d-afd5-733b9bf74c96" />

---

## Features

| Feature | Details |
|---|---|
| **Dynamic form** | Three sections — Yesterday, Today, Blockers — each with unlimited rows and inline editing |
| **Multiple Jira tickets per row** | Each standup item supports zero, one, or many tickets (searched from Jira or entered manually) |
| **Jira search + JQL** | Debounced Jira search with pagination, auto-detecting JQL queries and showing ticket status |
| **Automatic Jira links** | Generates `[TICKET-123](https://…/browse/TICKET-123)` using your configured base URL |
| **Slack mentions** | Supports `@username` tagging in entries and resolves mentions to Slack user IDs when sending |
| **Send to Slack (channel or thread)** | Dispatch your standup directly to a channel or to a thread from the in-app picker |
| **Multi-dispatch mode** | Option to keep the send modal open and send the same status to multiple channels |
| **Blockers toggle** | "No Blockers / Yes, I Have Blockers" segmented control with conditional blockers section |
| **Settings + secure credentials** | Jira and Slack credentials are stored securely in Keychain; app settings persist in UserDefaults |
| **Scheduled notifications** | Local notifications at the configured time on selected weekdays; clicking focuses the app |
| **Light / Dark mode** | Full native macOS aesthetic |

---

## Project Structure

```
Standapp/
├── StandappApp.swift          # @main entry point, Scene setup
├── Models/
│   ├── StandupItem.swift      # Standup entry model (text + tickets + tagged users)
│   └── AppSettings.swift      # @Observable app state and preferences
├── Views/
│   ├── ContentView.swift      # Root view (settings toolbar button)
│   ├── StandupFormView.swift  # Main form (three sections + action bar)
│   ├── StandupSectionView.swift # Dynamic rows, ticket picker, mentions
│   └── SettingsView.swift     # Integrations, credentials, notification schedule
├── Services/
│   ├── SettingsStore.swift    # UserDefaults persistence (save/load)
│   ├── StandupFormatter.swift # Produces the final Markdown string
│   └── NotificationManager.swift # UNUserNotificationCenter scheduling
├── Jira/                       # Jira credentials, search, models, picker UI
├── Slack/                      # Slack token, channels/threads, dispatch UI
├── Assets.xcassets/           # App icon and accent color
├── Info.plist
└── Standapp.entitlements
```

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15 or later

---

## Build & Run

1. Open `Standapp.xcodeproj` in Xcode.
2. Select the **Standapp** scheme and a macOS destination.
3. Press **⌘R** to build and run.

---

## Configuration

Open **Settings** (gear icon in the toolbar or ⌘,):

- **JIRA Base URL** — e.g. `https://company.atlassian.net` (used for Markdown ticket links)
- **Jira credentials** — subdomain, email, and API token (stored in Keychain)
- **Slack Bot Token** — required for loading channels/threads and sending messages (stored in Keychain)
- **Slack Channel URI** — e.g. `slack://channel?team=T0001&id=C0001`
- **Reminder Time & Days** — pick hour, minute, and weekdays; click **Save & Schedule**
- Click **Request Notification Permission** on first launch.

### Credential setup

- **Jira API Token**: generate it at `id.atlassian.com` → **Security** → **API tokens**.
- **Slack Bot Token**: create an app at `api.slack.com/apps` and copy the **Bot User OAuth Token** (`xoxb-...`).
- Credentials are never displayed back in plain text once saved.

---

## Usage Example

1. At the scheduled time a system notification appears.  
2. Click it — the app opens/focuses.  
3. Fill in entries for Yesterday and Today; optionally tag teammates with `@username`.  
4. Add one or multiple Jira tickets per row (search popup or manual key input).  
5. Toggle blockers as needed.  
6. Click **Send to Slack** and choose destination: **Channel** or **Thread**.  
7. Send, and optionally keep the modal open with **Send to multiple channels**.

### Output example

```
**Yesterday**
• Fixed login redirect bug [DEV-101](https://company.atlassian.net/browse/DEV-101)

**Today**
• Implement notification scheduler [DEV-102](https://company.atlassian.net/browse/DEV-102)

**Blockers**
• No blockers
```

---

## Troubleshooting

- **Slack Unauthorized (401)**: re-open Settings and save a valid bot token again.
- **No Jira search results**: verify Jira credentials and try a broader query or explicit JQL.
- **Notifications not showing**: ensure notification permission is enabled in macOS System Settings.
