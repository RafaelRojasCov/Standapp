import SwiftUI

struct ContentView: View {

    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false

    var body: some View {
        StandupFormView()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(settings)
                    .frame(minWidth: 460, minHeight: 420)
            }
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
}
