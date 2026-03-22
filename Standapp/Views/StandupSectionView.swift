import AppKit
import SwiftUI

// MARK: - Section View

/// Renders one standup section (Yesterday / Today / Blockers).
struct StandupSectionView: View {

    var title: String?
    @Binding var items: [StandupItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            ForEach($items) { $item in
                StandupItemRowView(item: $item) {
                    removeItem(item)
                }
            }

            Button {
                withAnimation(.easeIn(duration: 0.15)) {
                    items.append(StandupItem())
                }
            } label: {
                Label("Add another", systemImage: "plus.circle")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.accentColor)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func removeItem(_ item: StandupItem) {
        guard items.count > 1 else {
            items[0] = StandupItem()
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            items.removeAll { $0.id == item.id }
        }
    }
}

// MARK: - Item Row View

/// Layout:
///   [ Status description (grows with ticket column height) ] [ DEV-101  ⊗ ]
///                                                             [ DEV-102  ⊗ ]
///                                                             [ Search…  🔍 ]
///   [ @mention field (inline autocomplete) ]
///   [ — ]
struct StandupItemRowView: View {

    @Binding var item: StandupItem
    var onRemove: () -> Void

    @State private var showJiraPicker = false

    private let keychain = KeychainManager.shared
    private let ticketColumnWidth: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {

                // ── Description field (grows to match ticket column height) ───
                MentionTextField(
                    text: $item.text,
                    taggedUsers: $item.taggedUsers
                )
                .frame(maxWidth: .infinity)

                // ── Ticket column ─────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($item.tickets) { $ticket in
                        TicketChipView(ticket: $ticket) {
                            removeTicket(ticket)
                        }
                    }

                    if keychain.hasJiraCredentials {
                        HStack(spacing: 4) {
                            Text(item.tickets.isEmpty ? "e.g. DEV-101" : "Add ticket…")
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .frame(width: ticketColumnWidth, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                )
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Color.accentColor)
                                .font(.callout)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { showJiraPicker = true }
                        .popover(isPresented: $showJiraPicker, arrowEdge: .bottom) {
                            JiraTicketPickerPopover(
                                selectedTickets: $item.tickets,
                                isPresented: $showJiraPicker
                            )
                            .frame(width: 480, height: 440)
                        }
                    } else {
                        ManualTicketField(tickets: $item.tickets)
                    }
                }

                // ── Remove button ─────────────────────────────────────────────
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .frame(width: 22)
                .padding(.top, 1)
                .help("Remove this entry")
            }
        }
    }

    private func removeTicket(_ ticket: SelectedTicket) {
        withAnimation {
            item.tickets.removeAll { $0.id == ticket.id }
        }
    }
}

// MARK: - MentionTextField

/// A multi-line text field that detects `@` and shows a user autocomplete popover.
/// On selection, replaces the `@query` fragment with `@username` and records the TaggedUser.
struct MentionTextField: View {

    @Binding var text: String
    @Binding var taggedUsers: [TaggedUser]

    @State private var mentionQuery: String = ""
    @State private var showPopover = false
    @State private var mentionRange: NSRange? = nil
    @State private var coordinatorRef: MentionTextViewRepresentable.Coordinator? = nil

    private let userStore = SlackUserStore.shared

    var body: some View {
        MentionTextViewRepresentable(
            text: $text,
            onMentionStarted: { query, range in
                mentionQuery = query
                mentionRange = range
                showPopover = true
                Task { await userStore.loadIfNeeded() }
            },
            onMentionUpdated: { query, range in
                mentionQuery = query
                mentionRange = range
            },
            onMentionEnded: {
                showPopover = false
                mentionRange = nil
            },
            onMentionInserted: {
                // Reset coordinator isMentioning so next @ correctly fires onMentionStarted
                showPopover = false
                mentionRange = nil
            },
            onCoordinatorCreated: { coordinator in
                coordinatorRef = coordinator
            }
        )
        .frame(maxWidth: .infinity, minHeight: 28)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            MentionSuggestionsView(
                query: mentionQuery,
                users: userStore.filter(mentionQuery),
                isLoading: userStore.isLoading
            ) { user in
                insertMention(user)
            }
            .frame(width: 240, height: 200)
        }
    }

    private func insertMention(_ user: SlackUser) {
        guard let range = mentionRange else { return }

        // Replace @query with @username in the text
        let nsText = text as NSString
        guard range.location != NSNotFound,
              range.location + range.length <= nsText.length else { return }

        let replacement = "@\(user.username)"
        text = nsText.replacingCharacters(in: range, with: replacement)

        // Record tagged user (avoid duplicates)
        if !taggedUsers.contains(where: { $0.id == user.id }) {
            taggedUsers.append(TaggedUser(id: user.id, username: user.username))
        }

        // Reset coordinator so next @ triggers onMentionStarted again
        coordinatorRef?.resetMentionState()
        showPopover = false
        mentionRange = nil
    }
}

// MARK: - MentionTextViewRepresentable

/// NSViewRepresentable wrapping NSTextView to detect @ typing and track cursor position.
struct MentionTextViewRepresentable: NSViewRepresentable {

    @Binding var text: String
    var onMentionStarted: (String, NSRange) -> Void
    var onMentionUpdated: (String, NSRange) -> Void
    var onMentionEnded: () -> Void
    var onMentionInserted: () -> Void  // called after a user is picked to reset coordinator state
    var onCoordinatorCreated: (Coordinator) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 4)

        // Match rounded border style
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        context.coordinator.textView = textView
        onCoordinatorCreated(context.coordinator)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Only update if source of truth changed externally (avoid cursor jump)
        if textView.string != text {
            textView.string = text
            context.coordinator.applyMentionColors(in: textView)
        }
        // Wire the insertion reset callback into the coordinator via the parent reference
        context.coordinator.parent = self
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MentionTextViewRepresentable
        weak var textView: NSTextView?
        private(set) var isMentioning = false
        private var mentionStart: Int = 0

        init(_ parent: MentionTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string

            let cursorPos = tv.selectedRange().location
            let nsString = tv.string as NSString

            // Find the last @ before cursor on the same line
            if let atRange = findActiveMentionRange(in: nsString, cursorPos: cursorPos) {
                let query = nsString.substring(with: NSRange(
                    location: atRange.location + 1,
                    length: cursorPos - atRange.location - 1
                ))
                // Range covers from @ to cursor
                let fullRange = NSRange(location: atRange.location, length: cursorPos - atRange.location)

                if !isMentioning {
                    isMentioning = true
                    mentionStart = atRange.location
                    parent.onMentionStarted(query, fullRange)
                } else {
                    parent.onMentionUpdated(query, fullRange)
                }
            } else if isMentioning {
                isMentioning = false
                parent.onMentionEnded()
            }

            applyMentionColors(in: tv)
        }

        func textDidEndEditing(_ notification: Notification) {
            if isMentioning {
                isMentioning = false
                parent.onMentionEnded()
            }
        }

        /// Resets mention tracking after a user has been inserted from the popover.
        func resetMentionState() {
            isMentioning = false
            mentionStart = 0
        }

        /// Finds the NSRange of the `@` character that starts an active mention
        /// (i.e., `@` followed only by word characters up to cursorPos, no spaces).
        private func findActiveMentionRange(in string: NSString, cursorPos: Int) -> NSRange? {
            guard cursorPos > 0 else { return nil }
            let searchStart = max(0, cursorPos - 50) // look back up to 50 chars
            let sub = string.substring(with: NSRange(location: searchStart, length: cursorPos - searchStart))
            // Find the last @ that has no space between it and the cursor
            guard let atIndex = sub.lastIndex(of: "@") else { return nil }
            let afterAt = sub[sub.index(after: atIndex)...]
            // If there's a space or newline between @ and cursor, mention ended
            if afterAt.contains(" ") || afterAt.contains("\n") { return nil }
            let atOffset = sub.distance(from: sub.startIndex, to: atIndex)
            return NSRange(location: searchStart + atOffset, length: 1)
        }

        /// Colors all `@username` tokens in the text view blue.
        func applyMentionColors(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            // Reset to default first
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

            // Highlight @word tokens
            let pattern = "@[\\w\\.]+"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let matches = regex.matches(in: storage.string, range: fullRange)
            for match in matches {
                storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
            }
        }
    }
}

// MARK: - Mention Suggestions Popover

private struct MentionSuggestionsView: View {
    let query: String
    let users: [SlackUser]
    let isLoading: Bool
    let onSelect: (SlackUser) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading users…").controlSize(.small)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else if users.isEmpty {
                Text(query.isEmpty ? "Type to search users" : "No users found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(users) { user in
                    Button {
                        onSelect(user)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.circle")
                                .foregroundStyle(.secondary)
                            Text(user.username)
                                .font(.callout)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Manual Ticket Field (no Jira credentials)

private struct ManualTicketField: View {
    @Binding var tickets: [SelectedTicket]
    @State private var text: String = ""
    private let width: CGFloat = 160

    var body: some View {
        TextField(tickets.isEmpty ? "e.g. DEV-101" : "Add ticket…", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospaced())
            .frame(width: width)
            .onSubmit {
                let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !tickets.contains(where: { $0.id == key }) else {
                    text = ""
                    return
                }
                tickets.append(SelectedTicket(key: key))
                text = ""
            }
    }
}

// MARK: - Ticket Chip

/// Displays a single selected ticket with a remove button.
struct TicketChipView: View {
    @Binding var ticket: SelectedTicket
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(ticket.id)
                .font(.callout.monospaced())
                .lineLimit(1)

            if !ticket.statusName.isEmpty {
                Text(ticket.statusName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(statusColor(ticket.statusCategory))
                    .clipShape(Capsule())
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .frame(width: 160, alignment: .leading)
    }

    private func statusColor(_ category: String) -> Color {
        switch category {
        case "In Progress": return Color(red: 0.00, green: 0.45, blue: 0.89)
        case "Done":        return Color(red: 0.07, green: 0.65, blue: 0.47)
        default:            return Color(red: 0.55, green: 0.60, blue: 0.65)
        }
    }
}

// MARK: - Jira Ticket Picker Popover

struct JiraTicketPickerPopover: View {

    @Binding var selectedTickets: [SelectedTicket]
    @Binding var isPresented: Bool

    @State private var viewModel = JiraViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Jira…", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { Task { await viewModel.performSearch() } }
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(12)

            if !selectedTickets.isEmpty {
                HStack {
                    Text("\(selectedTickets.count) ticket\(selectedTickets.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { isPresented = false }
                        .font(.caption.bold())
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()

            Group {
                switch viewModel.loadingState {
                case .idle:
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("Type to search your Jira tickets")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loading:
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loaded, .loadingMore:
                    List(viewModel.tickets) { ticket in
                        let isSelected = selectedTickets.contains(where: { $0.id == ticket.id })
                        Button {
                            toggleTicket(ticket)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ticket.id)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(ticket.summary)
                                        .font(.callout)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                                StatusBadgeView(
                                    category: ticket.statusCategory,
                                    label: ticket.statusName
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .task { await viewModel.loadMoreIfNeeded(currentItem: ticket) }
                    }
                    .listStyle(.plain)

                case .error(let msg):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundStyle(.red)
                        Text(msg)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Retry") { Task { await viewModel.performSearch() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { searchFocused = true }
        .alert(
            viewModel.alertError?.errorDescription ?? "Error",
            isPresented: $viewModel.showAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let suggestion = viewModel.alertError?.recoverySuggestion {
                Text(suggestion)
            }
        }
    }

    private func toggleTicket(_ ticket: JiraTicket) {
        if let idx = selectedTickets.firstIndex(where: { $0.id == ticket.id }) {
            selectedTickets.remove(at: idx)
        } else {
            let selected = SelectedTicket(
                id: ticket.id,
                statusName: ticket.statusName,
                statusCategory: ticket.statusCategory.rawValue
            )
            selectedTickets.append(selected)
        }
    }
}

// MARK: - Preview

#Preview {
    StandupSectionView(
        title: "Yesterday",
        items: .constant([
            StandupItem(
                text: "Fixed login bug @ana",
                tickets: [
                    SelectedTicket(id: "DEV-101", statusName: "In Progress", statusCategory: "In Progress"),
                    SelectedTicket(id: "DEV-102", statusName: "Done", statusCategory: "Done")
                ],
                taggedUsers: [TaggedUser(id: "U01", username: "ana")]
            )
        ])
    )
    .padding()
    .frame(width: 680)
}
