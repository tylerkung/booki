import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            Text("Dashboard")
                .font(.title)
                .navigationTitle("Dashboard")
        }
    }
}

#Preview {
    DashboardView()
}
