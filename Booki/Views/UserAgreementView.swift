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
                .font(Theme.font(size: 60))
                .foregroundStyle(Theme.accent)

            Text("Terms of Service")
                .font(Theme.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func messageView(_ message: String) -> some View {
        HStack {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.warning)

            Text(message)
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(TermsOfService.summary)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private var viewFullTermsButton: some View {
        Button {
            showingFullTerms = true
        } label: {
            HStack {
                Image(systemName: "doc.plaintext")
                Text("View Full Terms")
            }
            .font(Theme.subheadline)
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
                    .font(Theme.title2)
                    .foregroundStyle(hasAgreed ? Theme.accent : Theme.textSecondary)

                Text("I have read and agree to the Terms of Service")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding()
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            onAccept()
        } label: {
            Text("Continue")
                .font(Theme.headline)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)
                .padding()
                .background(hasAgreed ? Theme.accent : Theme.accent.opacity(0.5))
                .foregroundStyle(hasAgreed ? Theme.background : Theme.background.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
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
                    Text(TermsOfService.fullTerms)
                        .font(Theme.body)
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
