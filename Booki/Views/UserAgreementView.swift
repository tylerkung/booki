import SwiftUI

/// View for displaying and accepting the Terms of Service
/// Users must accept before accessing the app
struct UserAgreementView: View {

    // MARK: - Properties

    /// Callback when the user accepts the agreement
    var onAccept: () -> Void

    /// Optional message to show at the top (e.g., for updated terms)
    var message: String?

    // MARK: - State

    @State private var hasAgreed: Bool = false
    @State private var showingFullTerms: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerView

                    // Optional message (e.g., for updated terms)
                    if let message = message {
                        messageView(message)
                    }

                    // Agreement summary
                    summaryView

                    // View Full Terms button
                    viewFullTermsButton

                    // Agreement checkbox
                    agreementToggle

                    // Continue button
                    continueButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showingFullTerms) {
            FullTermsSheet()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)

            Text("Terms of Service")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func messageView(_ message: String) -> some View {
        HStack {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.warning)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.1))
        .cornerRadius(Theme.cornerRadiusSmall)
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Placeholder summary text - will be replaced by TermsOfService.summary in US-005
            Text("IMPORTANT: Please read carefully before continuing.")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("""
                Booki is a record-keeping and bet management tool. By using Booki, you acknowledge and agree that:

                • Booki does NOT place, accept, or process bets on your behalf
                • Booki does NOT hold, transfer, or process any money or payments
                • All financial arrangements between bookies and players occur entirely outside this app
                • Booki serves only as an organizational tool to track bets and balances
                • You are solely responsible for ensuring your activities comply with all applicable local, state, and federal laws
                • Booki makes no representations about the legality of sports betting in your jurisdiction

                This app is provided for record-keeping and entertainment purposes only. Booki is not a licensed sportsbook, gambling operator, or financial institution.

                By continuing, you confirm that you are at least 18 years old (or the legal age in your jurisdiction) and accept these terms.
                """)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadius)
    }

    private var viewFullTermsButton: some View {
        Button {
            showingFullTerms = true
        } label: {
            HStack {
                Image(systemName: "doc.plaintext")
                Text("View Full Terms")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(Theme.accent)
        }
    }

    private var agreementToggle: some View {
        Button {
            hasAgreed.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: hasAgreed ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(hasAgreed ? Theme.accent : Theme.textSecondary)

                Text("I have read and agree to the Terms of Service")
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding()
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cornerRadiusSmall)
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            onAccept()
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(hasAgreed ? Theme.accent : Theme.accent.opacity(0.5))
                .foregroundStyle(hasAgreed ? Theme.background : Theme.background.opacity(0.5))
                .cornerRadius(Theme.cornerRadiusSmall)
        }
        .disabled(!hasAgreed)
    }
}

// MARK: - Full Terms Sheet

/// Sheet displaying the full Terms of Service text
private struct FullTermsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Placeholder full terms - will be replaced by TermsOfService.fullTerms in US-005
                    Text("""
                        BOOKI TERMS OF SERVICE

                        Last Updated: January 2026

                        1. ACCEPTANCE OF TERMS

                        By accessing or using the Booki application ("App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use the App.

                        2. DESCRIPTION OF SERVICE

                        Booki is a record-keeping and bet management tool designed to help users track bets and balances. Booki does NOT:
                        - Place, accept, or process bets on behalf of users
                        - Hold, transfer, or process any money or payments
                        - Function as a sportsbook, gambling operator, or financial institution

                        All financial arrangements between users occur entirely outside this App.

                        3. USER RESPONSIBILITIES

                        You are solely responsible for:
                        - Ensuring your activities comply with all applicable local, state, and federal laws
                        - Any financial arrangements made outside of this App
                        - Maintaining the security of your account credentials

                        4. AGE REQUIREMENT

                        You must be at least 18 years old (or the legal age in your jurisdiction) to use this App.

                        5. DISCLAIMER OF WARRANTIES

                        THE APP IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND. BOOKI MAKES NO REPRESENTATIONS ABOUT THE LEGALITY OF SPORTS BETTING IN YOUR JURISDICTION.

                        6. LIMITATION OF LIABILITY

                        IN NO EVENT SHALL BOOKI BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES ARISING OUT OF YOUR USE OF THE APP.

                        7. DATA USAGE

                        Booki may collect and store data necessary for the operation of the App. Your data is used solely for providing the service and is not sold to third parties.

                        8. TERMINATION

                        Booki reserves the right to terminate or suspend your access to the App at any time, for any reason, without notice.

                        9. CHANGES TO TERMS

                        Booki may modify these Terms at any time. Continued use of the App after changes constitutes acceptance of the modified Terms.

                        10. CONTACT

                        For questions about these Terms, please contact support through the App.
                        """)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(4)
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Full Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    UserAgreementView(onAccept: {
        print("Agreement accepted")
    })
}

#Preview("With Message") {
    UserAgreementView(
        onAccept: {
            print("Agreement accepted")
        },
        message: "We have updated our Terms of Service. Please review and accept to continue."
    )
}
