# Standapp — macOS Daily Standup Assistant

A native macOS application (SwiftUI, macOS 13+) that streamlines daily standup reporting by formatting your answers and JIRA ticket links into clean Markdown for Slack.

---

## Features

| Feature | Details |
|---|---|
| **Dynamic form** | Three sections — Yesterday, Today, Blockers — each with unlimited rows (text area + ticket ID) |
| **JIRA ticket linking** | Combines a configurable base URL with the ticket ID to produce `[TICKET-123](https://…/browse/TICKET-123)` |
| **Jira Cloud search** | Debounced JQL search (`POST /rest/api/3/search`) for assigned tickets with native multi-selection |
| **Blockers toggle** | "Not Answered / No Blockers / Yes, I Have Blockers" segmented control; disables submit until answered |
| **Copy & Open Slack** | Aggregates all inputs into Markdown, copies to clipboard, then opens the configured Slack channel via URI scheme |
| **Settings** | JIRA base URL, Slack channel URI, scheduled time & weekdays — all persisted via UserDefaults |
| **Scheduled notifications** | Local notifications at the configured time on selected weekdays; clicking focuses the app |
| **Light / Dark mode** | Full native macOS aesthetic |

---

## Project Structure

```
Standapp/
├── StandappApp.swift          # @main entry point, Scene setup
├── Models/
│   ├── StandupItem.swift      # Identifiable Codable model (text + ticketId)
│   └── AppSettings.swift      # ObservableObject — all settings + today's draft
├── Views/
│   ├── ContentView.swift      # Root view (settings toolbar button)
│   ├── StandupFormView.swift  # Main form (three sections + action bar)
│   ├── StandupSectionView.swift # Dynamic rows with Add/Remove
│   └── SettingsView.swift     # JIRA URL, Slack URI, scheduler
├── Services/
│   ├── SettingsStore.swift    # UserDefaults persistence (save/load)
│   ├── StandupFormatter.swift # Produces the final Markdown string
│   └── NotificationManager.swift # UNUserNotificationCenter scheduling
├── Assets.xcassets/           # App icon and accent color
├── Info.plist
└── Standapp.entitlements
```

---

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15 or later

---

## Build & Run

1. Open `Standapp.xcodeproj` in Xcode.
2. Select the **Standapp** scheme and a macOS destination.
3. Press **⌘R** to build and run.

---

## Configuration

Open **Settings** (gear icon in the toolbar or ⌘,):

- **Jira Subdomain** — e.g. `company`
- **Jira Email + API Token** — securely stored in macOS Keychain
- **JIRA Base URL** — e.g. `https://company.atlassian.net`
- **Slack Channel URI** — e.g. `slack://channel?team=T0001&id=C0001`
- **Reminder Time & Days** — pick hour, minute, and weekdays; click **Save & Schedule**
- Click **Request Notification Permission** on first launch.

---

## Usage Example

1. At the scheduled time a system notification appears.  
2. Click it — the app opens/focuses.  
3. Fill in entries for Yesterday and Today; add ticket IDs (e.g. `DEV-101`).  
4. Toggle blockers as needed.  
5. Click **Copy Standup & Open Slack**.  
6. Paste in Slack — the text is already formatted and the channel opens automatically.

### Output example

```
**Yesterday**
• Fixed login redirect bug [DEV-101](https://company.atlassian.net/browse/DEV-101)

**Today**
• Implement notification scheduler [DEV-102](https://company.atlassian.net/browse/DEV-102)

**Blockers**
• No blockers
```
