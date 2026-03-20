import SwiftUI
import AppKit

struct StandupFormView: View {

    @Environment(AppSettings.self) private var settings
    @State private var copyConfirmed = false
    @State private var alertMessage: String?

    var body: some View {
        @Bindable var settings = settings
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
        .alert("Unable to open Slack", isPresented: Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented { alertMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
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

            Picker("", selection: $settings.blockerState) {
                Text("Not Answered").tag(BlockerState.unanswered)
                Text("No Blockers").tag(BlockerState.noBlockers)
                Text("Yes, I Have Blockers").tag(BlockerState.hasBlockers)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            if settings.blockerState == .hasBlockers {
                StandupSectionView(
                    title: nil,
                    items: $settings.blockersItems
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: settings.blockerState)
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
            .disabled(!isFormReadyToSubmit)
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

    private var isFormReadyToSubmit: Bool {
        let yesterdayHasContent = settings.yesterdayItems
            .contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let todayHasContent = settings.todayItems
            .contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return yesterdayHasContent
            && todayHasContent
            && settings.blockerState != .unanswered
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
        guard !uriString.isEmpty, let url = URL(string: uriString) else {
            alertMessage = "Your standup was copied to the clipboard. Please verify the Slack URI in Settings and paste manually."
            return
        }
        if !NSWorkspace.shared.open(url) {
            alertMessage = "Slack could not be opened. Your standup is already copied to the clipboard; paste it manually."
        }
    }

    private func clearAll() {
        settings.yesterdayItems = [StandupItem()]
        settings.todayItems     = [StandupItem()]
        settings.blockerState   = .unanswered
        settings.blockersItems  = [StandupItem()]
    }
}

#Preview {
    StandupFormView()
        .environment(AppSettings())
        .frame(width: 780, height: 560)
}
