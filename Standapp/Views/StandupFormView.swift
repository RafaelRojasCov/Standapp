import SwiftUI
import AppKit

struct StandupFormView: View {

    @Environment(AppSettings.self) private var settings
    @State private var copyConfirmed = false
    @State private var alertMessage: String?

    var body: some View {
        @Bindable var bindableSettings = settings
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        StandupSectionView(
                            title: "🗓 Yesterday",
                            items: $bindableSettings.yesterdayItems
                        )

                        Divider()

                        StandupSectionView(
                            title: "📋 Today",
                            items: $bindableSettings.todayItems
                        )

                        Divider()

                        blockersSection
                    }
                    .padding(20)
                }

                Divider()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            VStack(spacing: 0) {
                previewPanel

                Divider()

                JiraTicketsView()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                Divider()

                actionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var blockersSection: some View {
        @Bindable var viewSettings = settings
        return VStack(alignment: .leading, spacing: 12) {
            Text("🚧 Blockers")
                .font(.headline)

            Picker("", selection: $viewSettings.blockerState) {
                Text("No Blockers").tag(BlockerState.noBlockers)
                Text("Yes, I Have Blockers").tag(BlockerState.hasBlockers)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)

            if viewSettings.blockerState == .hasBlockers {
                StandupSectionView(
                    title: nil,
                    items: $viewSettings.blockersItems
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: settings.blockerState)
    }

    private var actionBar: some View {
        HStack {
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
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var previewPanel: some View {
        ScrollView {
            Text(markdownPreviewText)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Helpers

    private var previewText: String {
        StandupFormatter(settings: settings).format()
    }

    private var markdownPreviewText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: previewText, options: options))
            ?? AttributedString(previewText)
    }

    private var isFormReadyToSubmit: Bool {
        let yesterdayHasContent = settings.yesterdayItems
            .contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let todayHasContent = settings.todayItems
            .contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return yesterdayHasContent
            && todayHasContent
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
        guard !uriString.isEmpty,
              let url = URL(string: uriString),
              url.scheme?.lowercased() == "slack" else {
            alertMessage = "Your standup was copied to the clipboard. Please verify the Slack URI in Settings and paste manually."
            return
        }
        if !NSWorkspace.shared.open(url) {
            alertMessage = "Slack could not be opened. Your standup is already copied to the clipboard; paste it manually."
        }
    }

}

#Preview {
    StandupFormView()
        .environment(AppSettings())
        .frame(width: 780, height: 560)
}
