import Foundation
import StoreKit
@preconcurrency import Supabase

/// Service for managing Apple IAP subscriptions via StoreKit 2.
@Observable
@MainActor
final class StoreKitService {

    // MARK: - Singleton

    static let shared = StoreKitService()

    // MARK: - Product IDs

    static let proMonthlyProductId = "com.bookisports.booki.pro.monthly"

    // MARK: - Published State

    var product: Product?
    var isEntitled = false
    var isPurchasing = false
    var errorMessage: String?

    // MARK: - Private

    private var updateListenerTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    /// Start listening for transaction updates (renewals, cancellations, refunds).
    /// Call this once on app launch.
    func startTransactionListener() {
        updateListenerTask?.cancel()
        updateListenerTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handleVerifiedTransaction(result)
            }
        }
    }

    /// Stop the transaction listener.
    func stopTransactionListener() {
        updateListenerTask?.cancel()
        updateListenerTask = nil
    }

    // MARK: - Load Products

    /// Load the Pro monthly subscription product from the App Store.
    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proMonthlyProductId])
            product = products.first
        } catch {
            print("StoreKitService: Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    /// Purchase the Pro monthly subscription.
    /// - Returns: `true` if purchase succeeded, `false` otherwise.
    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            // Product not loaded yet — try loading before giving up
            await loadProducts()
            guard let product = self.product else {
                errorMessage = "Product not available. Please try again."
                return false
            }
            return await purchaseProduct(product)
        }

        return await purchaseProduct(product)
    }

    private func purchaseProduct(_ product: Product) async -> Bool {
        isPurchasing = true
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                // Send to server (best-effort — don't block upgrade on server failure)
                await sendTransactionToServer(transaction)
                await transaction.finish()
                isEntitled = true
                isPurchasing = false
                return true

            case .userCancelled:
                isPurchasing = false
                return false

            case .pending:
                errorMessage = "Purchase is pending approval."
                isPurchasing = false
                return false

            @unknown default:
                isPurchasing = false
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            isPurchasing = false
            return false
        }
    }

    // MARK: - Restore Purchases

    /// Restore purchases — syncs with App Store to recover entitlements.
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkCurrentEntitlement()
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlement Check

    /// Check if the user currently has an active Pro subscription.
    /// Call on app launch for catch-up.
    func checkCurrentEntitlement() async {
        var foundEntitlement = false

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.productID == Self.proMonthlyProductId {
                    foundEntitlement = true
                    // Send to server in case it was missed
                    await sendTransactionToServer(transaction)
                }
            }
        }

        isEntitled = foundEntitlement
    }

    // MARK: - Private Helpers

    /// Verify a transaction result from StoreKit.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }

    /// Handle an incoming transaction update (renewal, refund, etc.).
    private func handleVerifiedTransaction(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }

        if transaction.productID == Self.proMonthlyProductId {
            if transaction.revocationDate != nil {
                // Refunded or revoked
                isEntitled = false
            } else if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                // Expired
                isEntitled = false
            } else {
                isEntitled = true
            }

            await sendTransactionToServer(transaction)
            await transaction.finish()
        }
    }

    /// Send the verified transaction JWS to our edge function for server-side validation.
    private func sendTransactionToServer(_ transaction: Transaction) async {
        // Get the JWS representation
        guard let jwsRepresentation = await latestJWS(for: transaction.productID) else {
            print("StoreKitService: Could not get JWS for transaction")
            return
        }

        do {
            let _: AppleIAPResponse = try await EdgeFunctionService.shared.callFunction(
                name: "apple_iap_webhook",
                body: AppleIAPRequest(transactionJWS: jwsRepresentation)
            )
        } catch {
            print("StoreKitService: Failed to send transaction to server: \(error)")
        }
    }

    /// Get the latest JWS string for a product.
    private func latestJWS(for productID: String) async -> String? {
        guard let result = await Transaction.latest(for: productID) else { return nil }
        return result.jwsRepresentation
    }
}

// MARK: - Request/Response Models

private struct AppleIAPRequest: Encodable {
    let transactionJWS: String
}

private struct AppleIAPResponse: Decodable {
    let success: Bool
    let error: String?
}
