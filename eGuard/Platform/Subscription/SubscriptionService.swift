import Observation
import StoreKit

/// Reads the eGuard Plus entitlement from StoreKit. The free plan is the honest default
/// until a product exists in App Store Connect.
@Observable
final class SubscriptionService {
    static let plusProductID = "com.eguard.plus.yearly"

    enum Plan: Equatable {
        case free
        case plus(renews: Date?)

        var title: String {
            switch self {
            case .free: "eGuard Free"
            case .plus: "eGuard Plus"
            }
        }

        var statusText: String {
            switch self {
            case .free: "Current Plan"
            case .plus: "Active Plan"
            }
        }

        var isPlus: Bool {
            if case .plus = self { return true }
            return false
        }
    }

    private(set) var plan: Plan = .free
    private(set) var product: Product?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        product = try? await Product.products(for: [Self.plusProductID]).first
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.plusProductID,
               transaction.revocationDate == nil {
                plan = .plus(renews: transaction.expirationDate)
                return
            }
        }
        plan = .free
    }

    /// Finishes a verified purchase result from SwiftUI's purchase action.
    func handle(_ result: Product.PurchaseResult) async {
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                await refreshEntitlements()
            } else {
                errorMessage = "The App Store could not verify this purchase."
            }
        case .pending:
            errorMessage = "The purchase is waiting for approval."
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
