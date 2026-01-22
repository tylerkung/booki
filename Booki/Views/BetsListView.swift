import SwiftUI

struct BetsListView: View {
    var body: some View {
        NavigationStack {
            Text("Bets")
                .font(.title)
                .navigationTitle("Bets")
        }
    }
}

#Preview {
    BetsListView()
}
