import Foundation
import StoreKit

@MainActor
class SubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro: Bool = false
    @Published private(set) var purchaseError: String?
    @Published private(set) var isRestoring: Bool = false
    // Guards against propagating Pro status to a Firestore user doc before the
    // current StoreKit session has actually been queried for entitlements.
    @Published private(set) var hasLoaded: Bool = false

    static let monthlyID = "com.tommychiu.marque.pro.monthly"
    static let annualID  = "com.tommychiu.marque.pro.annual"

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load

    func load() async {
        defer { hasLoaded = true }
        guard products.isEmpty else { await refreshProStatus(); return }
        do {
            products = try await Product.products(for: [Self.annualID, Self.monthlyID])
                .sorted { $0.price > $1.price }
        } catch {
            // Products not configured in App Store Connect yet — silent in dev
        }
        await refreshProStatus()
    }

    func reset() {
        isPro = false
        purchaseError = nil
        hasLoaded = false
    }

    // MARK: - Purchase

    func clearError() { purchaseError = nil }

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshProStatus()
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshProStatus()
        } catch {
            purchaseError = "Restore failed. Please try again."
        }
    }

    // MARK: - Status

    func refreshProStatus() async {
        var hasActiveSubscription = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               (transaction.productID == Self.monthlyID || transaction.productID == Self.annualID),
               transaction.revocationDate == nil {
                hasActiveSubscription = true
                break
            }
        }
        isPro = hasActiveSubscription
    }

    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyID } }
    var annualProduct:  Product? { products.first { $0.id == Self.annualID } }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await self?.refreshProStatus()
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreKitError.notEntitled
        case .verified(let value): return value
        }
    }
}
