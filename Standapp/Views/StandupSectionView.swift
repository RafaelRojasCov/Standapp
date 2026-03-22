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
///   [ Status description…  ] [ DEV-101  ⊗ ]
///                             [ DEV-102  ⊗ ]  ← extra tickets
///                             [ Search…  🔍 ] ← search field / add button
///   [ — ]
struct StandupItemRowView: View {

    @Binding var item: StandupItem
    var onRemove: () -> Void

    @State private var showJiraPicker = false

    private let keychain = KeychainManager.shared
    private let ticketColumnWidth: CGFloat = 160

    var body: some View {
        HStack(alignment: .top, spacing: 10) {

            // ── Description field ──────────────────────────────────────────
            TextField("Status description…", text: $item.text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .padding(.top, 1) // visual alignment with first ticket chip

            // ── Ticket column ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                // Existing tickets
                ForEach($item.tickets) { $ticket in
                    TicketChipView(ticket: $ticket) {
                        removeTicket(ticket)
                    }
                }

                // Search / add field
                if keychain.hasJiraCredentials {
                    // Tapping opens the Jira picker; the field itself is non-interactive.
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
                    // No Jira credentials — plain manual entry field
                    ManualTicketField(tickets: $item.tickets)
                }
            }

            // ── Remove row button ──────────────────────────────────────────
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

    private func removeTicket(_ ticket: SelectedTicket) {
        withAnimation {
            item.tickets.removeAll { $0.id == ticket.id }
        }
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
            // Search bar
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

            // Selection count hint
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

            // Results
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
                                // Checkmark indicator
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
        .onAppear {
            searchFocused = true
        }
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

    // MARK: -

    private func toggleTicket(_ ticket: JiraTicket) {
        if let idx = selectedTickets.firstIndex(where: { $0.id == ticket.id }) {
            // Deselect
            selectedTickets.remove(at: idx)
        } else {
            // Select — carry status info for the formatter
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
                text: "Fixed login bug",
                tickets: [
                    SelectedTicket(id: "DEV-101", statusName: "In Progress", statusCategory: "In Progress"),
                    SelectedTicket(id: "DEV-102", statusName: "Done", statusCategory: "Done")
                ]
            )
        ])
    )
    .padding()
    .frame(width: 680)
}
