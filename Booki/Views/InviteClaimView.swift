import SwiftUI

/// View for claiming an invite via deep link or manual code entry.
/// Handles both new user signup and existing user login paths.
struct InviteClaimView: View {

    /// Pre-filled invite code from deep link (booki://invite/{code})
    let initialCode: String?

    /// Navigate back to login screen
    let onNavigateToLogin: () -> Void

    /// Called when invite claim is fully complete (player joined)
    let onClaimComplete: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Image("BookiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)

                Text("Invite Claim")
                    .font(Theme.title)
                    .foregroundStyle(Theme.textPrimary)

                if let code = initialCode {
                    Text("Code: \(code)")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                Button("Back to Login") {
                    onNavigateToLogin()
                }
                .font(Theme.headline)
                .foregroundStyle(Theme.accent)
            }
            .padding()
        }
    }
}

#Preview {
    InviteClaimView(
        initialCode: "ABC12345",
        onNavigateToLogin: {},
        onClaimComplete: {}
    )
}
