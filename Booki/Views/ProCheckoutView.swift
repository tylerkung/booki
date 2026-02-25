import SwiftUI
import SwiftData
@preconcurrency import Supabase

// MARK: - Request/Response Models

private struct CheckoutSessionRequest: Encodable {}

private struct CheckoutSessionResponse: Decodable {
    let success: Bool
    let sessionId: String?
    let url: String?
    let error: String?
}

/// Checkout screen for Pro subscription — calls Stripe via edge function.
struct ProCheckoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bookies: [Bookie]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var checkoutURL: URL?
    @State private var showingSuccess = false

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

                    // Stripe badge
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.textMuted)

                        Text("Secure payment powered by Stripe")
                            .font(Theme.bodyFont(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 20)
                    .cardStyle()
                    .padding(.horizontal, 16)

                    // Error message
                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.bodyFont(size: 13))
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Pay button
                    Button {
                        Task { await startCheckout() }
                    } label: {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(Theme.background)
                            }
                            Text("Pay $49.99 / month")
                                .font(Theme.font(size: 17, weight: .bold))
                                .foregroundStyle(Theme.background)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isLoading ? Theme.accent.opacity(0.6) : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    }
                    .disabled(isLoading)
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
        .sheet(isPresented: Binding(
            get: { checkoutURL != nil },
            set: { if !$0 { checkoutURL = nil } }
        )) {
            if let url = checkoutURL {
                StripeCheckoutWebView(url: url) { success in
                    checkoutURL = nil
                    if success {
                        handleCheckoutSuccess()
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showingSuccess) {
            ProSuccessView()
        }
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

    private func startCheckout() async {
        isLoading = true
        errorMessage = nil

        do {
            let response: CheckoutSessionResponse = try await EdgeFunctionService.shared.callFunction(
                name: "create_checkout_session",
                body: CheckoutSessionRequest()
            )

            if response.success, let urlString = response.url, let url = URL(string: urlString) {
                await MainActor.run {
                    checkoutURL = url
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    errorMessage = response.error ?? "Failed to create checkout session"
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func handleCheckoutSuccess() {
        // Update local tier immediately
        if let bookie = bookies.first {
            bookie.tier = .pro
            try? modelContext.save()
        }
        showingSuccess = true
    }
}

// MARK: - Stripe Checkout Web View

import WebKit

struct StripeCheckoutWebView: UIViewRepresentable {
    let url: URL
    let onComplete: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let onComplete: (Bool) -> Void

        init(onComplete: @escaping (Bool) -> Void) {
            self.onComplete = onComplete
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if let url = navigationAction.request.url {
                // Intercept deep link redirects from Stripe
                if url.scheme == "booki" {
                    if url.host == "checkout-success" {
                        await MainActor.run { onComplete(true) }
                    } else {
                        await MainActor.run { onComplete(false) }
                    }
                    return .cancel
                }
            }
            return .allow
        }
    }
}

#Preview {
    NavigationStack {
        ProCheckoutView()
    }
}
