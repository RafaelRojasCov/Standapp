import SwiftUI
import AppKit

struct StandupFormView: View {

    @EnvironmentObject private var settings: AppSettings
    @State private var copyConfirmed = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            headerBar

            Divider()

            // ── Scrollable sections ───────────────────────────────────────────
            ScrollView {
                VStack(spacing: 24) {
                    StandupSectionView(
                        title: "🗓 Yesterday",
                        items: $settings.yesterdayItems
                    )

                    Divider()

                    StandupSectionView(
                        title: "📋 Today",
                        items: $settings.todayItems
                    )

                    Divider()

                    blockersSection
                }
                .padding(20)
            }

            Divider()

            // ── Action bar ────────────────────────────────────────────────────
            actionBar
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Sub-views

    private var headerBar: some View {
        HStack {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Daily Standup")
                .font(.title2).bold()
            Spacer()
            Button(role: .destructive) {
                clearAll()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("Clear all entries")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var blockersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🚧 Blockers")
                .font(.headline)

            // Toggle between "No blockers" and "Yes, I have blockers"
            Picker("", selection: $settings.hasBlockers) {
                Text("No Blockers").tag(false)
                Text("Yes, I Have Blockers").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            if settings.hasBlockers {
                StandupSectionView(
                    title: nil,
                    items: $settings.blockersItems
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: settings.hasBlockers)
    }

    private var actionBar: some View {
        HStack {
            // Preview area
            Text(previewText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            Button {
                copyAndOpenSlack()
            } label: {
                Label(
                    copyConfirmed ? "Copied! ✓" : "Copy Standup & Open Slack",
                    systemImage: copyConfirmed ? "checkmark.circle.fill" : "doc.on.clipboard"
                )
                .font(.callout.bold())
            }
            .buttonStyle(.borderedProminent)
            .disabled(isFormEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var previewText: String {
        let formatted = StandupFormatter(settings: settings).format()
        let preview   = formatted.prefix(120)
        return preview.count < formatted.count ? String(preview) + "…" : String(preview)
    }

    private var isFormEmpty: Bool {
        let allEmpty = (settings.yesterdayItems + settings.todayItems)
            .allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return allEmpty
    }

    private func copyAndOpenSlack() {
        let text = StandupFormatter(settings: settings).format()

        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Provide brief visual confirmation
        withAnimation {
            copyConfirmed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { self.copyConfirmed = false }
        }

        // Open Slack via URI scheme
        let uriString = settings.slackChannelUri
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !uriString.isEmpty, let url = URL(string: uriString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func clearAll() {
        settings.yesterdayItems = [StandupItem()]
        settings.todayItems     = [StandupItem()]
        settings.hasBlockers    = false
        settings.blockersItems  = [StandupItem()]
    }
}

#Preview {
    StandupFormView()
        .environmentObject(AppSettings())
        .frame(width: 780, height: 560)
}
