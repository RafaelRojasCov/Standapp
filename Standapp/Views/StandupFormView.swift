import SwiftUI
import AppKit

struct StandupFormView: View {

    @Environment(AppSettings.self) private var settings
    @State private var showSlackDispatch = false

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

                actionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showSlackDispatch) {
            SlackDispatchView(messageText: previewText, taggedUsers: allTaggedUsers)
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
                showSlackDispatch = true
            } label: {
                Label("Send to Slack", systemImage: "paperplane.fill")
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

    /// Collects all unique tagged users across all standup sections.
    private var allTaggedUsers: [TaggedUser] {
        let all = settings.yesterdayItems + settings.todayItems + settings.blockersItems
        var seen = Set<String>()
        return all.flatMap { $0.taggedUsers }.filter { seen.insert($0.id).inserted }
    }

    private var isFormReadyToSubmit: Bool {
        let yesterdayHasContent = settings.yesterdayItems
            .contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let todayHasContent = settings.todayItems
            .contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return yesterdayHasContent
            && todayHasContent
    }

}

#Preview {
    StandupFormView()
        .environment(AppSettings())
        .frame(width: 780, height: 560)
}
