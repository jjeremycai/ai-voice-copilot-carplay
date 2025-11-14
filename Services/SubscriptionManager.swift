//
//  SubscriptionManager.swift
//  Shaw
//

import Foundation
import StoreKit

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var state: SubscriptionState
    @Published var availableProducts: [Product] = []
    @Published var isLoading = false

    private let productIds = [
        "com.vanities.shaw.pro.week",
        "com.vanities.shaw.pro.month",
        "com.vanities.shaw.pro.year"
    ]

    private let cache = EntitlementsCache.shared
    private let iapAPI = IAPAPI.shared

    private var transactionUpdateTask: Task<Void, Never>?

    private init() {
        self.state = cache.load() ?? .inactive
        transactionUpdateTask = Task { await observeTransactions() }
    }

    deinit {
        transactionUpdateTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            availableProducts = try await Product.products(for: productIds)
            print("📦 Loaded \(availableProducts.count) products")
        } catch {
            print("❌ Failed to load products: \(error)")
        }
    }

    func purchase(product: Product) async throws {
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await handle(transaction: transaction)
            case .unverified:
                throw SubscriptionError.verificationFailed
            }

        case .userCancelled:
            throw SubscriptionError.userCancelled

        case .pending:
            throw SubscriptionError.pending

        @unknown default:
            throw SubscriptionError.purchaseFailed
        }
    }

    func restore() async throws {
        isLoading = true
        defer { isLoading = false }

        try await AppStore.sync()
        
        // Check for active entitlements from App Store first
        var foundActiveEntitlement = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  productIds.contains(transaction.productID) else {
                continue
            }
            
            foundActiveEntitlement = true
            // Update local state immediately from App Store
            let newState = SubscriptionState.from(transaction: transaction)
            state = newState
            cache.save(state: newState)
            
            // Try to sync with backend, but don't fail if backend is unavailable
            do {
                let transactionData = "\(transaction.originalID)-\(transaction.productID)"
                let verifyResponse = try await iapAPI.verify(transactionJWS: transactionData)
                print("✅ Backend verification successful: isActive=\(verifyResponse.isActive)")
                
                // Update state with backend response if different
                if verifyResponse.isActive != newState.isActive {
                    let backendState = SubscriptionState(
                        status: verifyResponse.isActive ? .active : .expired,
                        productId: verifyResponse.productId,
                        originalTransactionId: verifyResponse.originalTransactionId,
                        expiresAt: verifyResponse.expiresAt,
                        isInGracePeriod: verifyResponse.isInGrace
                    )
                    state = backendState
                    cache.save(state: backendState)
                }
            } catch {
                // Backend sync failed, but restore should still succeed if we found an entitlement
                print("⚠️ Backend verification failed (backend may be unavailable): \(error)")
                // Continue - we've already updated state from App Store
            }
            
            await transaction.finish()
            break // Take the first active entitlement
        }
        
        // If no active entitlement found, mark as inactive
        if !foundActiveEntitlement {
            state = .inactive
            cache.save(state: state)
            throw SubscriptionError.verificationFailed
        }
    }

    func refreshEntitlementsAndSync() async {
        guard cache.needsRefresh() else {
            print("🔄 Entitlements cache fresh, skipping refresh")
            return
        }

        print("🔄 Refreshing entitlements...")

        var foundActiveEntitlement = false

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  productIds.contains(transaction.productID) else {
                continue
            }

            foundActiveEntitlement = true
            await handle(transaction: transaction)
            break // Take the first active entitlement
        }

        if !foundActiveEntitlement {
            state = .inactive
            cache.save(state: state)
        }
    }

    private func observeTransactions() async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update,
                  productIds.contains(transaction.productID) else {
                continue
            }

            print("📱 Transaction update received: \(transaction.productID)")
            await handle(transaction: transaction)
        }
    }

    private func handle(transaction: Transaction) async {
        print("📱 Handling transaction: \(transaction.productID)")

        // Update local state
        let newState = SubscriptionState.from(transaction: transaction)
        state = newState
        cache.save(state: newState)

        // Sync to backend
        do {
            // Create fake JWS for now - in production, we'd use transaction.jsonRepresentation
            // For testing, backend can work without full JWS validation
            let transactionData = "\(transaction.originalID)-\(transaction.productID)"

            let verifyResponse = try await iapAPI.verify(transactionJWS: transactionData)
            print("✅ Backend verification successful: isActive=\(verifyResponse.isActive)")

            // Update state with backend response if different
            if verifyResponse.isActive != newState.isActive {
                let backendState = SubscriptionState(
                    status: verifyResponse.isActive ? .active : .expired,
                    productId: verifyResponse.productId,
                    originalTransactionId: verifyResponse.originalTransactionId,
                    expiresAt: verifyResponse.expiresAt,
                    isInGracePeriod: verifyResponse.isInGrace
                )
                state = backendState
                cache.save(state: backendState)
            }
        } catch {
            print("❌ Backend verification failed: \(error)")
        }

        // Finish the transaction
        await transaction.finish()
    }
}
