import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var settings: AppSettings
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
                    .environmentObject(settings)
                    .frame(minWidth: 460, minHeight: 420)
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}
