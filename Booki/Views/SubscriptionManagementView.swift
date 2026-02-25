import SwiftUI
import SwiftData

/// Subscription management screen for Pro bookies to view plan details.
struct SubscriptionManagementView: View {
    @Query private var bookies: [Bookie]
    @Query private var players: [Player]
    @State private var showingManageAlert = false

    private var currentBookie: Bookie? {
        bookies.first
    }

    private var activeMemberCount: Int {
        guard let bookie = currentBookie else { return 0 }
        return players.filter { $0.bookieId == bookie.id && $0.authUserId != nil && $0.status == .active }.count
    }

    private var memberSinceDate: String {
        guard let bookie = currentBookie else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: bookie.createdAt)
    }

    private var nextRenewalDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        guard let nextDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) else {
            return "—"
        }
        return formatter.string(from: nextDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Current Plan header
                Text("CURRENT PLAN")
                    .font(Theme.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                    .padding(.bottom, -8)

                VStack(spacing: 0) {
                    // Plan name + Active pill
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Booki Pro")
                                .font(Theme.font(size: 20, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)

                            Text("$49.99 / month")
                                .font(Theme.bodyFont(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        Text("Active")
                            .font(Theme.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    dividerRow

                    detailRow(label: "Member Since", value: memberSinceDate)
                    dividerRow
                    detailRow(label: "Next Renewal", value: nextRenewalDate)
                    dividerRow

                    detailRow(label: "Members", value: "\(activeMemberCount) of 50")
                }
                .cardStyle()

                // Billing header
                Text("BILLING")
                    .font(Theme.caption)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                    .padding(.bottom, -8)

                VStack(spacing: 0) {
                    Button {
                        showingManageAlert = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28, alignment: .center)

                            Text("Manage on Stripe")
                                .font(Theme.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.textPrimary)

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .cardStyle()

                Text("Cancel anytime. Your existing members and data are preserved.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Coming Soon", isPresented: $showingManageAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Stripe billing portal will be available soon.")
        }
    }

    // MARK: - Private Helpers

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var dividerRow: some View {
        Divider()
            .background(Theme.border)
            .padding(.leading, 16)
    }
}

#Preview {
    NavigationStack {
        SubscriptionManagementView()
    }
    .modelContainer(for: [Bookie.self, Player.self], inMemory: true)
}
