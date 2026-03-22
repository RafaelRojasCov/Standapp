import SwiftUI

// MARK: - Status Badge

struct StatusBadgeView: View {
    let category: JiraStatusCategory
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(category.color)
            .clipShape(Capsule())
    }
}

// MARK: - Ticket Row

struct JiraTicketRowView: View {
    let ticket: JiraTicket
    let browseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(ticket.id)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                if let url = browseURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                StatusBadgeView(
                    category: ticket.statusCategory,
                    label: ticket.statusName
                )
            }

            Text(ticket.summary)
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Label(ticket.issueType, systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let assignee = ticket.assignee {
                    Label(assignee, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let priority = ticket.priority {
                    Label(priority, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Search View

struct JiraSearchView: View {

    @State private var viewModel = JiraViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search Jira tickets or enter JQL…", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { Task { await viewModel.performSearch() } }

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)

            Divider()

            // Results / States
            ZStack {
                switch viewModel.loadingState {
                case .idle:
                    idlePlaceholder

                case .loading:
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loaded, .loadingMore:
                    ticketList

                case .error(let message):
                    errorPlaceholder(message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { isSearchFocused = true }
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

    // MARK: - Sub-views

    private var idlePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Enter a search term or JQL query")
                .foregroundStyle(.secondary)
        }
    }

    private func errorPlaceholder(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                Task { await viewModel.performSearch() }
            }
        }
    }

    private var ticketList: some View {
        List(selection: $viewModel.selectedTicketIDs) {
            ForEach(viewModel.tickets) { ticket in
                JiraTicketRowView(
                    ticket: ticket,
                    browseURL: viewModel.browseURL(for: ticket)
                )
                .tag(ticket.id)
                .task { await viewModel.loadMoreIfNeeded(currentItem: ticket) }
            }

            if viewModel.loadingState == .loadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) {
            if !viewModel.selectedTicketIDs.isEmpty {
                selectionBar
            }
        }
    }

    private var selectionBar: some View {
        HStack {
            Text("\(viewModel.selectedTicketIDs.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Copy Keys") {
                let keys = viewModel.copySelectedKeys()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(keys, forType: .string)
            }
            .buttonStyle(.bordered)
            Button("Clear") {
                viewModel.clearSelection()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Jira Preferences View

struct JiraPreferencesView: View {

    @State private var viewModel = JiraViewModel()
    @State private var subdomain: String = ""
    @State private var email: String = ""
    @State private var apiToken: String = ""
    @State private var isSaved = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                Text("Jira Configuration")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 16) {
                    // Subdomain
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subdomain")
                            .font(.headline)
                        HStack {
                            TextField("yourcompany", text: $subdomain)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            Text(".atlassian.net")
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                        Text("The part before .atlassian.net in your Jira URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Email
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(.headline)
                        TextField("you@company.com", text: $email)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }

                    // API Token
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Token")
                            .font(.headline)
                        SecureField("Paste your API token", text: $apiToken)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        Text("Generate at id.atlassian.com/manage-profile/security/api-tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                HStack {
                    if viewModel.loadStoredCredentials() != nil {
                        Button("Remove Credentials", role: .destructive) {
                            viewModel.deleteCredentials()
                            subdomain = ""
                            email = ""
                            apiToken = ""
                            isSaved = false
                        }
                    }
                    Spacer()
                    Button("Save to Keychain") {
                        viewModel.saveCredentials(
                            subdomain: subdomain,
                            email: email,
                            apiToken: apiToken
                        )
                        isSaved = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(subdomain.isEmpty || email.isEmpty || apiToken.isEmpty)
                }

                if isSaved {
                    Label("Credentials saved securely in Keychain.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .padding(20)
        }
        .onAppear {
            if let creds = viewModel.loadStoredCredentials() {
                subdomain = creds.subdomain
                email     = creds.email
                // Do not pre-fill apiToken — treat as write-only
            }
        }
        .alert(
            viewModel.alertError?.errorDescription ?? "Error",
            isPresented: $viewModel.showAlert
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: - Previews

#Preview("Search") {
    JiraSearchView()
        .frame(width: 520, height: 560)
}

#Preview("Preferences") {
    JiraPreferencesView()
        .frame(width: 460, height: 500)
}

#Preview("Status Badge") {
    HStack {
        StatusBadgeView(category: .toDo, label: "To Do")
        StatusBadgeView(category: .inProgress, label: "In Progress")
        StatusBadgeView(category: .done, label: "Done")
    }
    .padding()
}
