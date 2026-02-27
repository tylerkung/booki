import SwiftUI
import SwiftData

/// Primary conversion screen for free-tier bookies.
/// Presented from multiple upsell entry points throughout the app.
struct ProUpgradeSheet: View {
    var contextMessage: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var bookies: [Bookie]
    @State private var showingSuccess = false

    private var storeKit: StoreKitService { StoreKitService.shared }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Logo + heading
                        VStack(spacing: 12) {
                            Image("BookiPro")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 200)

                            Text("\(storeKit.product?.displayPrice ?? "$59.99") / month")
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

                        Spacer(minLength: 200)
                    }
                }

                // Sticky bottom area
                stickyBottomArea
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
            .navigationDestination(isPresented: $showingSuccess) {
                ProSuccessView()
            }
        }
        .presentationDetents([.large])
        .task {
            await storeKit.loadProducts()
        }
    }

    // MARK: - Sticky Bottom

    private var stickyBottomArea: some View {
        VStack(spacing: 12) {
            Spacer()

            VStack(spacing: 12) {
                // Error message
                if let errorMessage = storeKit.errorMessage {
                    Text(errorMessage)
                        .font(Theme.bodyFont(size: 13))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }

                // Subscribe button
                Button {
                    Task {
                        let success = await storeKit.purchase()
                        if success {
                            // Update local tier immediately
                            if let bookie = bookies.first {
                                bookie.tier = .pro
                                try? modelContext.save()
                            }
                            showingSuccess = true
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if storeKit.isPurchasing {
                            ProgressView()
                                .tint(Theme.background)
                        }
                        Text("Subscribe for \(storeKit.product?.displayPrice ?? "$59.99")/mo")
                            .font(Theme.font(size: 17, weight: .bold))
                            .foregroundStyle(Theme.background)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(storeKit.isPurchasing || storeKit.product == nil ? Theme.accent.opacity(0.6) : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
                .disabled(storeKit.isPurchasing || storeKit.product == nil)

                // Restore Purchases
                Button {
                    Task { await storeKit.restorePurchases() }
                } label: {
                    Text("Restore Purchases")
                        .font(Theme.bodyFont(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                // Auto-renewal disclosure
                Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Manage in Settings > Apple ID > Subscriptions.")
                    .font(Theme.bodyFont(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // Terms + Privacy links
                HStack(spacing: 4) {
                    Link("Terms of Service", destination: URL(string: "https://bookisports.com/terms.html")!)
                        .underline()
                    Text("and")
                    Link("Privacy Policy", destination: URL(string: "https://bookisports.com/privacy.html")!)
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
