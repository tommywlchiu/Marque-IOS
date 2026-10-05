import Foundation
import StoreKit
import FirebaseAuth
import FirebaseFunctions

@MainActor
class SubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro: Bool = false
    // True when this device has a Pro entitlement but none of them is a direct
    // purchase by the signed-in Apple ID — i.e. Pro arrived through Family
    // Sharing. Such a member is Pro locally, but the server withholds `isPro`
    // (entitlement-hijack guard in syncEntitlement), so their Assistant and scan
    // limits stay at the free tier until they subscribe themselves. The paywall
    // uses this to explain that instead of re-selling a plan they half-have.
    @Published private(set) var isFamilyShared: Bool = false
    @Published private(set) var purchaseError: String?
    // Separate from purchaseError on purpose: ProUpgradeView's `.task { load() }`
    // runs unconditionally, including on the already-Pro screen, and a failed
    // product fetch there overwrites purchaseError with "Subscriptions aren't
    // available right now" — a message about buying, not restoring. Reusing it
    // for a failed restore() would flash that unrelated text (or silently say
    // nothing) to a Pro user who never tried to subscribe.
    @Published private(set) var restoreError: String?
    @Published private(set) var isRestoring: Bool = false
    // Set once load() has actually queried StoreKit for this session's
    // entitlements. Marque_PrototypeApp gates authService.setProStatus() on it,
    // so the previous account's in-memory Pro flag can't carry across a
    // sign-in flip before StoreKit has been asked. This store does not write
    // Firestore — server-side `isPro` is owned by the appStoreNotifications
    // webhook and the syncEntitlement callable.
    @Published private(set) var hasLoaded: Bool = false

    // NOTE: intentionally NOT prefixed with the bundle ID (com.tommychiu.marque.*).
    // Those exact strings are permanently claimed under a stale App Store Connect
    // app record (registered under the wrong bundle ID, com.marque.Marque-Prototype)
    // and can never be reused, even though that app is abandoned. Product IDs
    // don't need to match the bundle ID at all -- only be unique per account.
    static let monthlyID = "marque.pro.monthly"
    static let annualID  = "marque.pro.annual"

    private var transactionListener: Task<Void, Never>?
    private let functions = Functions.functions()

    // Session cache for the Apple appAccountToken. Purely an optimization to
    // avoid a callable round-trip on every purchase attempt — getAppAccountToken
    // is idempotent and always returns the same UUID, so correctness never
    // depends on this being populated.
    private var cachedAppAccountToken: UUID?

    // Last StoreKit transaction ID handed to the `syncEntitlement` callable this
    // session. Purely a de-duplicator: refreshProStatus() runs on launch, after
    // every purchase and on every Transaction.updates event, and the callable is
    // idempotent, so there is no point paying for a round-trip per call with the
    // same transaction. Reset by restore(), which is the user's explicit
    // "fix my subscription" action and must always re-attempt the sync.
    private var lastSyncedTransactionID: UInt64?

    // The Firebase uid these two caches above were populated under. Checked at
    // point-of-use (appAccountToken(), syncEntitlement()) rather than relying on
    // Marque_PrototypeApp's onChange(of: authService.authState) to fire a clean
    // authenticated → nil → authenticated transition first. If Auth's listener
    // ever hands us an authenticated → authenticated flip directly (reauth
    // landing on a different account, credential linking), a stale cache here
    // would attach account A's appAccountToken — or skip syncing because A's
    // transaction ID looked already-synced — to account B's session, permanently
    // misattributing B's subscription to A.
    private var cachedTokenUID: String?
    private var lastSyncedUID: String?

    init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load

    func load() async {
        defer { hasLoaded = true }
        // Key the retry on whether both known product IDs have actually
        // resolved, not on whether the array is merely non-empty.
        // `Product.products(for:)` does not throw for unresolvable IDs — it
        // silently returns only the subset that resolved. If only one of the
        // two resolves, `products` becomes non-empty and the old
        // `products.isEmpty` guard would cache that partial result forever,
        // leaving the other plan permanently nil.
        guard monthlyProduct == nil || annualProduct == nil else { await refreshProStatus(); return }
        do {
            products = try await Product.products(for: [Self.annualID, Self.monthlyID])
                .sorted { $0.price > $1.price }
            // Zero resolved takes this same success path — no thrown error —
            // so without this, the UI can't tell "still loading" from
            // "nothing will ever load." Surface it the same way a thrown
            // error does, and clear it once something resolves.
            purchaseError = products.isEmpty
                ? "Subscriptions aren't available right now. Please try again later."
                : nil
        } catch {
            // Products not configured in App Store Connect yet — silent in dev
            purchaseError = "Subscriptions aren't available right now. Please try again later."
        }
        await refreshProStatus()
    }

    func reset() {
        isPro = false
        isFamilyShared = false
        purchaseError = nil
        restoreError = nil
        hasLoaded = false
        // Must clear: the token is per-account, and this store outlives sign-out.
        cachedAppAccountToken = nil
        lastSyncedTransactionID = nil
        cachedTokenUID = nil
        lastSyncedUID = nil
    }

    // MARK: - Purchase

    func clearError() { purchaseError = nil }

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            // The appAccountToken is the ONLY link between this transaction and
            // the Firebase account, and Apple will not let it be attached after
            // the fact — a purchase made without one can never be resolved by
            // the appStoreNotifications webhook, so renewals and expirations
            // would silently never sync `isPro`. Fail the purchase rather than
            // sell a subscription the server can't attribute.
            guard let token = await appAccountToken() else {
                purchaseError = "Couldn't start the purchase. Check your connection and try again."
                return
            }
            let result = try await product.purchase(options: [.appAccountToken(token)])
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                // FR-11.4 `purchase_completed`. Only here: `.pending` isn't a
                // purchase yet, `.userCancelled` never becomes one, and an
                // unverified result has already thrown out of checkVerified.
                // Plan comes from the verified transaction's productID rather
                // than the Product passed in, so the event reflects what Apple
                // actually sold. An unrecognised productID reports nothing
                // rather than guessing a plan.
                if let plan = Self.analyticsPlan(for: transaction.productID) {
                    AnalyticsService.purchaseCompleted(plan: plan)
                }
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
        restoreError = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            // Restore is the explicit self-heal path — always re-run the server
            // sync, even if this transaction was already sent this session.
            lastSyncedTransactionID = nil
            await refreshProStatus()
        } catch {
            restoreError = "Restore failed. Please try again."
        }
    }

    // MARK: - Status

    func refreshProStatus() async {
        // Two independent questions, answered in ONE pass:
        //
        // (1) Is there ANY verified, non-revoked Pro entitlement? That alone
        //     unlocks the local paywall, so a Family Sharing member is Pro on
        //     this device exactly like the purchaser is.
        // (2) Which transaction, if any, should be handed to syncEntitlement?
        //     A direct purchase always wins when one exists. A Family Sharing
        //     transaction belongs to the purchaser, not to whoever is signed
        //     in on this device, so it must never grant server-side isPro —
        //     but it IS sent as a fallback so the server can record the
        //     FR-08.8 unlimited-car-count flag for this account (see the
        //     matching inAppOwnershipType check in functions/src/index.ts,
        //     which enforces that isPro is never granted off it).
        //
        // These must stay decoupled: folding ownershipType into the single
        // value that drove `isPro` is what locked family members out of the
        // paywall entirely. Transaction.currentEntitlements is an
        // AsyncSequence — it can only be consumed in a `for await`, and
        // iterating it twice starts two separate sequences, so both answers
        // come out of this one loop.
        var hasProEntitlement = false
        var hasDirectPurchase = false
        // The JWS lives on the VerificationResult, not on Transaction itself,
        // so capture both: the ID de-duplicates the server call, the JWS is what
        // the server re-verifies. A direct purchase always wins if one turns
        // up — see the ownership check below — but a Family Sharing
        // transaction is kept as a fallback candidate so the server still
        // gets *something* to verify when no direct purchase exists. The
        // server (syncEntitlement) is what actually decides what a
        // Family-Shared JWS is allowed to grant (never isPro — only the
        // FR-08.8 car-limit flag); this loop only decides which JWS to send.
        var syncCandidate: (id: UInt64, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.monthlyID || transaction.productID == Self.annualID,
                  transaction.revocationDate == nil
            else { continue }

            hasProEntitlement = true
            if transaction.ownershipType == .purchased {
                hasDirectPurchase = true
                syncCandidate = (transaction.id, result.jwsRepresentation)
                // Both questions are now settled — nothing later in the
                // sequence can change either answer.
                break
            } else if syncCandidate == nil {
                // Family-Shared fallback — only kept if no direct purchase
                // has been (or is later) found, since the guard above always
                // overwrites this with a direct purchase and breaks.
                syncCandidate = (transaction.id, result.jwsRepresentation)
            }
        }
        isPro = hasProEntitlement
        isFamilyShared = hasProEntitlement && !hasDirectPurchase

        if let syncCandidate {
            await syncEntitlement(transactionID: syncCandidate.id,
                                  signedTransaction: syncCandidate.jws)
        }
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

    // Fetches this account's Apple appAccountToken from the `getAppAccountToken`
    // Cloud Function, which mints one on first call and returns the same UUID
    // on every call after that. The token is attached to the purchase below so
    // Apple echoes it back — signed — in every App Store Server Notification,
    // letting appStoreNotifications resolve the owning Firebase uid without
    // trusting anything the client wrote to Firestore.
    //
    // Returns nil when the user is signed out or the call fails; the caller
    // must not proceed with the purchase in that case.
    private func appAccountToken() async -> UUID? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        if cachedTokenUID != uid {
            // Different account than whoever populated the cache last —
            // discard rather than hand out a token that would attach this
            // purchase to the wrong Firebase uid.
            cachedAppAccountToken = nil
            cachedTokenUID = uid
        }
        if let cachedAppAccountToken { return cachedAppAccountToken }
        do {
            let result = try await functions.httpsCallable("getAppAccountToken").call()
            guard let payload = result.data as? [String: Any],
                  let raw = payload["appAccountToken"] as? String,
                  let uuid = UUID(uuidString: raw) else { return nil }
            // The signed-in account can flip while this call is in flight. The
            // guard above ran before the await, so re-check: caching (or
            // returning) A's token now would attach A's mapping to B's
            // purchase. Discard instead — the caller treats nil as "don't
            // start the purchase", which is the safe direction.
            guard Auth.auth().currentUser?.uid == uid else { return nil }
            cachedAppAccountToken = uuid
            cachedTokenUID = uid
            return uuid
        } catch {
            return nil
        }
    }

    // Reconciles server-side `users/{uid}.isPro` with Apple's own signed record
    // of this subscription.
    //
    // Normally the appStoreNotifications webhook keeps that field current on its
    // own, resolving the appAccountToken attached at purchase time back to a
    // Firebase uid. But a token can only be attached to a purchase as it happens,
    // so a subscription whose token no longer maps to a live account — e.g. the
    // account that bought it was deleted and the user signed up again — is
    // stranded: every renewal notification lands on the webhook's "unresolved
    // token" path forever. This callable is the repair path. It hands Apple's
    // JWS straight to the server, which re-verifies the signature itself and
    // claims the dangling token mapping for the current account.
    //
    // We send only the signed blob. The server never reads an identity or an
    // entitlement out of what we send — uid comes from the Firebase Auth token,
    // Pro status comes from the JWS Apple signed.
    //
    // Best-effort and non-blocking for correctness: the local paywall already
    // runs off StoreKit's own verification (`isPro` above), so a failure here
    // only delays cross-device unlock until the next launch or Restore tap.
    private func syncEntitlement(transactionID: UInt64, signedTransaction: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if lastSyncedUID != uid {
            // Different account than whoever set lastSyncedTransactionID last —
            // a matching transaction ID here would be coincidental, not proof
            // this account already synced it.
            lastSyncedTransactionID = nil
            lastSyncedUID = uid
        }
        guard lastSyncedTransactionID != transactionID else { return }
        do {
            _ = try await functions.httpsCallable("syncEntitlement")
                .call(["signedTransaction": signedTransaction])
            // Same in-flight account-switch window as appAccountToken(): the
            // uid guard above ran before the await. Recording this transaction
            // as synced under a uid that is no longer current would suppress
            // the retry for whoever is signed in now.
            guard Auth.auth().currentUser?.uid == uid else { return }
            lastSyncedTransactionID = transactionID
        } catch {
            // Leave lastSyncedTransactionID unset so the next refresh retries.
        }
    }

    private static func analyticsPlan(for productID: String) -> AnalyticsService.SubscriptionPlan? {
        switch productID {
        case monthlyID: return .monthly
        case annualID:  return .annual
        default:        return nil
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreKitError.notEntitled
        case .verified(let value): return value
        }
    }
}
