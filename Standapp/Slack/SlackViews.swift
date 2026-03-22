import SwiftUI

// MARK: - Channel Row

struct SlackChannelRowView: View {
    let channel: SlackChannel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(channel.name)
                .font(.body)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Thread Message Row

private struct SlackThreadMessageRowView: View {
    let message: SlackThreadMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(message.username)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(message.text)
                .font(.body)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - SlackDispatchView

struct SlackDispatchView: View {

    @State private var viewModel: SlackDispatchViewModel
    @Environment(\.dismiss) private var dismiss

    init(messageText: String) {
        _viewModel = State(initialValue: SlackDispatchViewModel(messageText: messageText))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            destinationPicker
            Divider()
            contentLayer
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 480)
        .onAppear {
            Task { await viewModel.loadChannels() }
        }
        .onChange(of: viewModel.didSendSuccessfully) { _, sent in
            if sent && !viewModel.isMultiDispatchEnabled {
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Send Status to Slack")
                .font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(NSColor.darkGray).opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Destination Picker

    private var destinationPicker: some View {
        HStack(spacing: 8) {
            destinationTab(label: "Channel", icon: "number", mode: .channel)
            destinationTab(label: "Thread", icon: "bubble.left.and.bubble.right", mode: .thread)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func destinationTab(label: String, icon: String, mode: DispatchDestinationMode) -> some View {
        let selected = viewModel.destinationMode == mode
        return Button {
            viewModel.selectDestinationMode(mode)
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content layer (conditional on mode + step)

    @ViewBuilder
    private var contentLayer: some View {
        switch viewModel.destinationMode {
        case .channel:
            channelList

        case .thread:
            if viewModel.selectedChannel == nil {
                // Step 1: pick a channel
                channelList
            } else {
                // Step 2: pick a thread from that channel
                threadList
            }
        }
    }

    // MARK: - Channel list (step 1, shared)

    private var channelList: some View {
        VStack(spacing: 0) {
            searchBar(placeholder: "Search channels…", query: $viewModel.channelSearchQuery)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if viewModel.isLoadingChannels && viewModel.filteredChannels.isEmpty {
                centeredProgress("Loading channels…")
            } else {
                List(selection: $viewModel.selectedChannel) {
                    ForEach(viewModel.filteredChannels) { channel in
                        SlackChannelRowView(channel: channel)
                            .tag(channel)
                            .task {
                                let all = viewModel.filteredChannels
                                guard all.count > 0 else { return }
                                let threshold = max(0, all.count - max(1, all.count / 10))
                                if let idx = all.firstIndex(of: channel), idx >= threshold {
                                    await viewModel.loadMoreChannelsIfNeeded(currentItem: channel)
                                }
                            }
                    }
                    if viewModel.isLoadingChannels {
                        HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Thread list (step 2, thread mode only)

    private var threadList: some View {
        VStack(spacing: 0) {
            // Back button + channel name
            HStack(spacing: 6) {
                Button {
                    viewModel.selectedChannel = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                if let ch = viewModel.selectedChannel {
                    Image(systemName: "number")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(ch.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            searchBar(placeholder: "Search by sender or message…", query: $viewModel.threadSearchQuery)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if viewModel.isLoadingThreads {
                centeredProgress("Loading threads…")
            } else if viewModel.filteredThreadMessages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No threads in the last 24 hours")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $viewModel.selectedThread) {
                    ForEach(viewModel.filteredThreadMessages) { message in
                        SlackThreadMessageRowView(message: message)
                            .tag(message)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if let error = viewModel.inlineError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Toggle("Send to multiple channels", isOn: $viewModel.isMultiDispatchEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.didSendSuccessfully {
                    Label("Sent!", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button {
                    Task { await viewModel.send() }
                } label: {
                    if viewModel.isSending {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Sending…")
                        }
                    } else {
                        Text("Send Status")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSend)
            }
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Helpers

    private func searchBar(placeholder: String, query: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField(placeholder, text: query)
                .textFieldStyle(.plain)
            if !query.wrappedValue.isEmpty {
                Button { query.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(7)
    }

    private func centeredProgress(_ label: String) -> some View {
        HStack {
            Spacer()
            ProgressView(label).controlSize(.small)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Slack Preferences View

struct SlackPreferencesView: View {

    @State private var viewModel = SlackViewModel()
    @State private var tokenInput: String = ""
    @State private var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bot Token")
                    .font(.headline)
                SecureField(
                    isSaved ? "Token saved — enter new token to replace" : "xoxb-…",
                    text: $tokenInput
                )
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                Text("Create a Bot at api.slack.com/apps and copy the Bot User OAuth Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                if isSaved {
                    Button("Remove", role: .destructive) {
                        viewModel.deleteToken()
                        tokenInput = ""
                        isSaved = false
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                if isSaved {
                    Label("Saved", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Button("Save") {
                    viewModel.saveToken(tokenInput)
                    tokenInput = ""
                    isSaved = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(tokenInput.isEmpty)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .onAppear { isSaved = viewModel.hasToken }
        .alert(
            viewModel.alertError?.errorDescription ?? "Error",
            isPresented: $viewModel.showAlert
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: - Previews

#Preview("Dispatch Modal") {
    SlackDispatchView(messageText: "Yesterday: completed PR review\nToday: finishing tests\nBlockers: none")
        .frame(width: 500, height: 540)
}

#Preview("Preferences") {
    SlackPreferencesView()
        .frame(width: 460, height: 200)
        .padding()
}

#Preview("Channel Row") {
    List {
        SlackChannelRowView(channel: SlackChannel(id: "C001", name: "general"))
        SlackChannelRowView(channel: SlackChannel(id: "C002", name: "engineering"))
    }
    .frame(width: 300, height: 100)
}
