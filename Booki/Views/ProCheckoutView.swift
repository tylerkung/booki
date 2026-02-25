import SwiftUI

/// Checkout screen for Pro subscription (placeholder until Stripe integration).
struct ProCheckoutView: View {
    @Environment(\.dismiss) private var dismiss

    private var todayFormatted: String {
        Date.now.formatted(date: .long, time: .omitted)
    }

    private var renewalFormatted: String {
        let renewal = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
        return renewal.formatted(date: .long, time: .omitted)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Summary card
                    VStack(spacing: 16) {
                        HStack {
                            Text("Booki Pro")
                                .font(Theme.font(size: 17, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("$49.99")
                                .font(Theme.font(size: 17, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }

                        Divider().overlay(Theme.textMuted.opacity(0.3))

                        summaryRow("Billing", value: "Monthly")
                        summaryRow("Today's charge", value: "$49.99")
                        summaryRow("Next renewal", value: renewalFormatted)
                    }
                    .padding(20)
                    .cardStyle()
                    .padding(.horizontal, 16)

                    // Stripe placeholder
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.textMuted)

                        Text("Secure payment powered by Stripe")
                            .font(Theme.bodyFont(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)

                        Text("Payment integration coming soon")
                            .font(Theme.bodyFont(size: 13))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .padding(.horizontal, 20)
                    .cardStyle()
                    .padding(.horizontal, 16)

                    // Pay button (disabled)
                    Button {
                        // Stripe integration pending
                    } label: {
                        Text("Pay $49.99 / month")
                            .font(Theme.font(size: 17, weight: .bold))
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    }
                    .disabled(true)
                    .opacity(0.5)
                    .padding(.horizontal, 16)

                    // Footer
                    VStack(spacing: 8) {
                        Text("Cancel anytime from Settings")
                            .font(Theme.bodyFont(size: 13))
                            .foregroundStyle(Theme.textMuted)

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
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Private

    @ViewBuilder
    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont(size: 15))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.bodyFont(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

#Preview {
    NavigationStack {
        ProCheckoutView()
    }
}
