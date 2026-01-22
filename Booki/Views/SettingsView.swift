import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Settings")
                .font(.title)
                .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
