import SwiftUI

struct JiraTicketsView: View {
    @Environment(AppSettings.self) private var settings
    @StateObject private var viewModel = JiraViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jira Tickets")
                .font(.headline)

            TextField("Search by summary or key", text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.updateSearchText($0, subdomain: settings.jiraSubdomain) }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)

            List(selection: $viewModel.selectedTicketIDs) {
                ForEach(viewModel.tickets) { ticket in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ticket.key)
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(ticket.summary)
                                .lineLimit(2)
                        }
                        Spacer()
                        StatusBadgeView(statusName: ticket.statusName, category: ticket.statusCategory)
                    }
                    .tag(ticket.id)
                    .onAppear {
                        Task { await viewModel.fetchNextPageIfNeeded(currentTicket: ticket, subdomain: settings.jiraSubdomain) }
                    }
                }
            }
            .frame(minHeight: 220)

            HStack {
                if viewModel.isLoading || viewModel.isFetchingMore {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Open in Browser") {
                    viewModel.openSelectedInBrowser(subdomain: settings.jiraSubdomain)
                }
                .disabled(viewModel.selectedTicketIDs.isEmpty)
            }
        }
        .task {
            viewModel.updateSearchText("", subdomain: settings.jiraSubdomain)
            searchFocused = true
        }
        .alert("Jira", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
