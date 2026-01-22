import SwiftUI

struct GradingView: View {
    var body: some View {
        NavigationStack {
            Text("Grading")
                .font(.title)
                .navigationTitle("Grading")
        }
    }
}

#Preview {
    GradingView()
}
