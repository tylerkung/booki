import SwiftUI

/// Upsell landing page for standalone users to become an organizer
struct BecomeOrganizerView: View {

    /// Action when "Get Started" is tapped — wired by parent
    var onGetStarted: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Benefits
                benefitsSection

                // Free tier callout
                freeTierCallout

                // CTA
                ctaButton
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .background(Theme.background)
        .navigationTitle("Be an Organizer")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Ready to run your group?")
                .font(Theme.title2)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Turn your bet tracking into a full management platform.")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(spacing: 16) {
            benefitRow(icon: "person.3.fill", title: "Invite Members", subtitle: "Add friends to your group and manage their accounts")
            benefitRow(icon: "chart.bar.fill", title: "Live Dashboard", subtitle: "Real-time analytics, PnL tracking, and member insights")
            benefitRow(icon: "dollarsign.circle.fill", title: "Balance Management", subtitle: "Credit limits, settle ups, and full ledger history")
            benefitRow(icon: "gearshape.2.fill", title: "Full Control", subtitle: "Pick management, grading policies, and member settings")
            benefitRow(icon: "bolt.fill", title: "Auto-Pilot", subtitle: "Auto-accept, auto-grade, and auto-settle picks")
        }
        .padding()
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.bodyFont(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(subtitle)
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Free Tier Callout

    private var freeTierCallout: some View {
        VStack(spacing: 12) {
            Text("Start free — no credit card required")
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                calloutItem("3 members")
                calloutItem("Singles tracking")
                calloutItem("Auto-grading")
                calloutItem("Dashboard")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
        )
    }

    private func calloutItem(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)

            Text("Free plan includes: \(text)")
                .font(Theme.bodyFont(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            if let onGetStarted {
                onGetStarted()
            } else {
                print("become organizer tapped")
            }
        } label: {
            Text("GET STARTED")
                .primaryButtonStyle()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        BecomeOrganizerView()
    }
}
