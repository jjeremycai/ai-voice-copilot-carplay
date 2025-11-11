//
//  SubscriptionState.swift
//  Shaw
//

import Foundation
import StoreKit

struct SubscriptionState: Codable, Equatable {
    enum Status: String, Codable {
        case active
        case grace
        case expired
        case inactive
    }

    let status: Status
    let productId: String?
    let originalTransactionId: String?
    let expiresAt: Date?
    let isInGracePeriod: Bool

    var isActive: Bool {
        status == .active || status == .grace
    }

    var displayStatus: String {
        switch status {
        case .active: return "Pro – Active"
        case .grace: return "In Grace Period"
        case .expired: return "Expired"
        case .inactive: return "Inactive"
        }
    }

    static let inactive = SubscriptionState(
        status: .inactive,
        productId: nil,
        originalTransactionId: nil,
        expiresAt: nil,
        isInGracePeriod: false
    )

    static func from(transaction: Transaction) -> SubscriptionState {
        let now = Date()

        // Check expiration
        if let expirationDate = transaction.expirationDate {
            if expirationDate > now {
                // Check if in grace period
                let isGrace = transaction.revocationDate == nil &&
                             transaction.isUpgraded == false &&
                             expirationDate.timeIntervalSince(now) < 86400 // < 24 hours

                return SubscriptionState(
                    status: isGrace ? .grace : .active,
                    productId: transaction.productID,
                    originalTransactionId: String(transaction.originalID),
                    expiresAt: expirationDate,
                    isInGracePeriod: isGrace
                )
            } else {
                return SubscriptionState(
                    status: .expired,
                    productId: transaction.productID,
                    originalTransactionId: String(transaction.originalID),
                    expiresAt: expirationDate,
                    isInGracePeriod: false
                )
            }
        }

        // Revoked or no expiration date
        if transaction.revocationDate != nil {
            return SubscriptionState(
                status: .expired,
                productId: transaction.productID,
                originalTransactionId: String(transaction.originalID),
                expiresAt: transaction.revocationDate,
                isInGracePeriod: false
            )
        }

        return .inactive
    }
}

enum SubscriptionError: LocalizedError {
    case purchaseFailed
    case verificationFailed
    case userCancelled
    case pending
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .purchaseFailed:
            return "Purchase failed. Please try again."
        case .verificationFailed:
            return "Could not verify your purchase. Please try again."
        case .userCancelled:
            return "Purchase was cancelled."
        case .pending:
            return "Purchase is pending approval."
        case .unknown(let error):
            return "An error occurred: \(error.localizedDescription)"
        }
    }
}
