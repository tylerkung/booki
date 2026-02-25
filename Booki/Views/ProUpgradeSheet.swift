import SwiftUI

/// Primary conversion screen for free-tier bookies.
/// Presented from multiple upsell entry points throughout the app.
struct ProUpgradeSheet: View {
    var contextMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Logo + heading
                        VStack(spacing: 12) {
                            Image("BookiLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120)

                            Text("PRO")
                                .font(Theme.font(size: 32, weight: .bold))
                                .foregroundStyle(Theme.accent)

                            Text("$49.99 / month")
                                .font(Theme.bodyFont(size: 17, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 16)

                        // Context message (optional)
                        if let contextMessage {
                            Text(contextMessage)
                                .font(Theme.bodyFont(size: 15, weight: .medium))
                                .foregroundStyle(Theme.warning)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        // Feature list card
                        VStack(alignment: .leading, spacing: 14) {
                            featureRow("50 members")
                            featureRow("Multi-Pick")
                            featureRow("Performance by sport")
                            featureRow("Futures tracking")
                            featureRow("Recent activity")
                            featureRow("Smart filters & tags")
                            featureRow("Manual approval")
                            featureRow("Acceptance rules")
                            featureRow("Override & reverse")
                            featureRow("CSV export")
                            featureRow("Full history")
                        }
                        .padding(20)
                        .cardStyle()
                        .padding(.horizontal, 16)

                        Spacer(minLength: 80)
                    }
                }

                // Sticky bottom area
                VStack(spacing: 12) {
                    Spacer()

                    VStack(spacing: 12) {
                        NavigationLink {
                            ProCheckoutView()
                        } label: {
                            Text("Subscribe — $49.99/mo")
                                .font(Theme.font(size: 17, weight: .bold))
                                .foregroundStyle(Theme.background)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                        }

                        Button {
                            // Restore purchase — placeholder
                        } label: {
                            Text("Already Pro? Restore Purchase")
                                .font(Theme.bodyFont(size: 13))
                                .foregroundStyle(Theme.textMuted)
                        }

                        HStack(spacing: 4) {
                            Text("Terms of Service")
                                .underline()
                            Text("and")
                            Text("Privacy Policy")
                                .underline()
                        }
                        .font(Theme.bodyFont(size: 11))
                        .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(
                        LinearGradient(
                            colors: [Theme.background.opacity(0), Theme.background, Theme.background],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Private

    @ViewBuilder
    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
                .font(.system(size: 18))
            Text(text)
                .font(Theme.bodyFont(size: 15))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ProUpgradeSheet(contextMessage: "You've reached the 3-member limit")
        }
}
