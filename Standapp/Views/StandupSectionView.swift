import AppKit
import SwiftUI

/// Renders one standup section (Yesterday / Today / Blockers) with a list of
/// dynamic (text + ticket) entry rows and an "Add another" button.
struct StandupSectionView: View {

    /// Optional title — pass `nil` when embedding inside another header (Blockers).
    var title: String?

    @Binding var items: [StandupItem]
    private let ticketFieldWidth: CGFloat = 140
    private let removeButtonWidth: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            HStack(spacing: 10) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Ticket")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: ticketFieldWidth, alignment: .leading)

                Color.clear
                    .frame(width: removeButtonWidth)
            }

            ForEach($items) { $item in
                StandupItemRowView(item: $item, ticketFieldWidth: ticketFieldWidth, removeButtonWidth: removeButtonWidth) {
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

    // MARK: -

    private func removeItem(_ item: StandupItem) {
        guard items.count > 1 else {
            // Reset instead of removing the last row.
            items[0] = StandupItem()
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            items.removeAll { $0.id == item.id }
        }
    }
}

// MARK: - Row

/// A single row: one-line status field (left) + ticket ID field (right).
struct StandupItemRowView: View {

    @Binding var item: StandupItem
    var ticketFieldWidth: CGFloat
    var removeButtonWidth: CGFloat
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Status description…", text: $item.text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            TextField("e.g. DEV-101", text: $item.ticketId)
                .textFieldStyle(.roundedBorder)
                .frame(width: ticketFieldWidth)
                .font(.callout.monospaced())

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .frame(width: removeButtonWidth)
            .help("Remove this entry")
        }
    }
}

#Preview {
    StandupSectionView(
        title: "Yesterday",
        items: .constant([StandupItem(text: "Fixed login bug", ticketId: "DEV-101")])
    )
    .padding()
    .frame(width: 600)
}
