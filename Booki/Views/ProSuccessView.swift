import SwiftUI

/// Success confirmation shown after successful Pro subscription payment.
struct ProSuccessView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var checkmarkScale: CGFloat = 0.5
    @State private var checkmarkOpacity: Double = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Animated checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.accent)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)

                VStack(spacing: 12) {
                    Text("Welcome to Pro")
                        .font(Theme.font(size: 28, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("You now have access to 50 members, Multi-Picks, full analytics, and every Pro feature.")
                        .font(Theme.bodyFont(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Get Started button
                Button {
                    dismiss()
                } label: {
                    Text("Get Started")
                        .primaryButtonStyle()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProSuccessView()
    }
}
