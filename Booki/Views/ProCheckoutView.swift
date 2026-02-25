import SwiftUI

/// Checkout screen for Pro subscription (placeholder until Stripe integration).
/// Full implementation in US-003.
struct ProCheckoutView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text("Checkout")
                .font(Theme.title2)
                .foregroundStyle(Theme.textPrimary)
        }
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
    }
}
