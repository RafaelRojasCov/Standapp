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
| **Dynamic form** | Three sections — Yesterday, Today, Blockers — each with unlimited rows (text area + ticket ID) |
| **JIRA ticket linking** | Combines a configurable base URL with the ticket ID to produce `[TICKET-123](https://…/browse/TICKET-123)` |
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
