import SwiftUI

struct PlayersListView: View {
    var body: some View {
        NavigationStack {
            Text("Players")
                .font(.title)
                .navigationTitle("Players")
        }
    }
}

#Preview {
    PlayersListView()
}
