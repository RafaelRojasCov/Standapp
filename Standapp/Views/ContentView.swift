import SwiftUI

struct ContentView: View {

    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false

    var body: some View {
        StandupFormView()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(role: .destructive) {
                        clearAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Clear all entries")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Open Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(settings)
                    .frame(minWidth: 460, minHeight: 420)
            }
    }

    private func clearAll() {
        settings.yesterdayItems = [StandupItem()]
        settings.todayItems = [StandupItem()]
        settings.blockerState = .noBlockers
        settings.blockersItems = [StandupItem()]
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
}
