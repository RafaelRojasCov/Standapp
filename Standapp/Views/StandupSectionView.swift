import AppKit
import SwiftUI

/// Renders one standup section (Yesterday / Today / Blockers) with a list of
/// dynamic (text + ticket) entry rows and an "Add another" button.
struct StandupSectionView: View {

    /// Optional title — pass `nil` when embedding inside another header (Blockers).
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

/// A single row: description text editor (left) + ticket ID field (right).
struct StandupItemRowView: View {

    @Binding var item: StandupItem
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Multi-line description editor
            ZStack(alignment: .topLeading) {
                if item.text.isEmpty {
                    Text("Description…")
                        .foregroundColor(Color(NSColor.placeholderTextColor))
                        .padding(.leading, 5)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $item.text)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            }

            // Ticket ID (narrow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ticket")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. DEV-101", text: $item.ticketId)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .font(.callout.monospaced())
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .padding(.top, 24)
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
