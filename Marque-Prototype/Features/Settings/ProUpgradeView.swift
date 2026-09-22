import SwiftUI
import StoreKit

struct ProUpgradeView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var subscriptionStore: SubscriptionStore

    // FR-11.5: which gate brought the user here. Deliberately has no default —
    // a default would let a call site silently mislabel its own trigger.
    let trigger: AnalyticsService.PaywallTrigger

    @State private var selectedPlan: PlanOption = .annual

    private enum PlanOption { case monthly, annual }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if subscriptionStore.isPro && !subscriptionStore.isFamilyShared {
                        alreadyProSection
                        proLegalLinks
                    } else if subscriptionStore.isFamilyShared {
                        // Pro via Family Sharing: unlimited cars and the badge are
                        // already theirs (free to serve), but the server withholds
                        // isPro for a family entitlement, so the metered features —
                        // FR-08's actual conversion driver — stay at the free tier.
                        // Still offer the same purchase flow as a non-Pro user: a
                        // direct purchase here is what unlocks it (see
                        // familySharedHero's comment on why this is safe to sync).
                        familySharedHero
                        planPicker
                        selectedPlanCard
                        familySharedFeatureList
                        ctaButton
                        legalFooter
                    } else {
                        heroSection
                        planPicker
                        selectedPlanCard
                        featureList
                        ctaButton
                        legalFooter
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
            .navigationTitle("Marque Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // "Done" only for a fully-resolved Pro user with nothing left to
                    // do here; a Family Sharing member still has a live CTA, so they
                    // get "Not Now" like a non-Pro user.
                    Button(subscriptionStore.isPro && !subscriptionStore.isFamilyShared ? "Done" : "Not Now") { dismiss() }
                        .foregroundColor(.secondary)
                }
            }
            .task { await subscriptionStore.load() }
            // Fires on appearance, not on the subscribe tap: the metric is the
            // conversion denominator (how many saw this gate). Skipped only when
            // fully already-Pro (nothing to convert) — a Family Sharing member
            // still sees a real purchase CTA here, so they count. isPro is read
            // at appearance: a not-yet-resolved entitlement (false for an instant
            // after launch) still counts, and the dismiss-on-flip below closes it.
            .onAppear {
                if !subscriptionStore.isPro || subscriptionStore.isFamilyShared {
                    AnalyticsService.paywallViewed(trigger: trigger)
                }
            }
            .onChange(of: subscriptionStore.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            // A Family Sharing member who then buys their own subscription stays
            // isPro == true throughout, so the onChange above never fires for them.
            // isFamilyShared flipping true -> false is the actual "just converted"
            // signal (refreshProStatus sets it false once a direct purchase exists).
            .onChange(of: subscriptionStore.isFamilyShared) { wasFamilyShared, isFamilyShared in
                if wasFamilyShared && !isFamilyShared { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
            }

            // FR-08's positioning: Pro anchors on metered AI usage (the
            // Assistant), because that's the only feature with real recurring
            // marginal cost. Leads with that rather than the generic
            // "unlock everything" framing FR-08.7 was written to retire.
            VStack(spacing: 6) {
                Text("More from Marque Assistant")
                    .font(.title2).fontWeight(.bold)
                Text("50x the daily messages, plus unlimited cars and a Pro badge on your profile.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // Shown instead of the paywall when this device is Pro via a DIRECT
    // purchase (never reached for Family Sharing — see familySharedHero).
    private var alreadyProSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 6) {
                Text("You're on Marque Pro")
                    .font(.title2).fontWeight(.bold)
                Text("Marque Pro is active on this device. If your daily limits still look like the free plan, tap Restore Purchases to re-sync your account.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error = subscriptionStore.restoreError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Restore Purchases") {
                Task { await subscriptionStore.restore() }
            }
            .buttonStyle(.bordered)
            .disabled(subscriptionStore.isRestoring)
            .padding(.top, 6)
        }
    }

    // Shown to a Family Sharing member instead of alreadyProSection. Their
    // Transaction.currentEntitlements already includes a FAMILY_SHARED Pro
    // entry, but purchasing here creates a PURCHASED one; SubscriptionStore.
    // refreshProStatus() prefers a PURCHASED transaction when picking what to
    // sync (see its `hasDirectPurchase` / `syncCandidate` logic), so this needs
    // no store changes — the existing sync already does the right thing.
    private var familySharedHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 6) {
                Text("Get More From Marque Assistant")
                    .font(.title2).fontWeight(.bold)
                Text("You already have the Pro badge and unlimited cars through Family Sharing. Subscribing on your own Apple ID adds 500 Assistant messages and \(ScanAllowanceStore.proDailyCap) document scans a day.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var planPicker: some View {
        Picker("Plan", selection: $selectedPlan.animation()) {
            Text("Annual").tag(PlanOption.annual)
            Text("Monthly").tag(PlanOption.monthly)
        }
        .pickerStyle(.segmented)
    }

    private var selectedPlanCard: some View {
        Group {
            switch selectedPlan {
            case .annual:
                PlanCard(
                    price: subscriptionStore.annualProduct?.displayPrice ?? "$24.99",
                    period: "/ year",
                    badge: "Save 30%",
                    detail: "That's just $2.08 / month. Cancel anytime."
                )
            case .monthly:
                PlanCard(
                    price: subscriptionStore.monthlyProduct?.displayPrice ?? "$2.99",
                    period: "/ month",
                    badge: nil,
                    detail: "Billed monthly. Cancel anytime."
                )
            }
        }
    }

    // FR-08.7: every benefit shown here must correspond to a gate actually
    // enforced in code, and a benefit free users already get must not be
    // advertised as a reason to subscribe. This is the exact mistake FR-08.7
    // was written to prevent — the v1.1 paywall advertised four benefits,
    // three of which were ungated. Smart Alerts, Expense Analytics, and
    // Social Profile are explicitly free per FR-08's positioning note (a
    // notification toggle, expense aggregation, and profile visibility all
    // ship to every user), so they were removed rather than reworded.
    // FR-08.9: cross-check this list against isPro's actual call sites
    // (`grep -rn "isPro" Marque-Prototype/ functions/src/index.ts`) before
    // adding or changing an entry.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Everything in Pro")
                .font(.headline)

            let features: [(icon: String, title: String, subtitle: String)] = [
                ("bubble.left.and.bubble.right.fill", "Marque Assistant", "500 messages a day, up from 10 free"),
                ("doc.text.viewfinder",               "Document Scans",   "\(ScanAllowanceStore.proDailyCap) scans a day, up from \(ScanAllowanceStore.freeDailyCap) free"),
                ("infinity",                          "Unlimited Cars",   "Free plan is limited to 3 vehicles"),
                ("checkmark.seal.fill",               "Pro Badge",        "Shown next to your name in Garage and Settings"),
            ]

            ForEach(features, id: \.title) { feat in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feat.icon)
                        .font(.body)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feat.title).font(.subheadline).fontWeight(.semibold)
                        Text(feat.subtitle).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // FR-08.7 applies here too, in the other direction: a Family Sharing member
    // already has Unlimited Cars and the Pro Badge, so — unlike featureList —
    // this must NOT list them; doing so would advertise a benefit they already
    // get for free as a reason to pay, the exact mistake FR-08.7 forbids.
    private var familySharedFeatureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What subscribing personally adds")
                .font(.headline)

            let features: [(icon: String, title: String, subtitle: String)] = [
                ("bubble.left.and.bubble.right.fill", "Marque Assistant", "500 messages a day, up from 10 free"),
                ("doc.text.viewfinder",               "Document Scans",   "\(ScanAllowanceStore.proDailyCap) scans a day, up from \(ScanAllowanceStore.freeDailyCap) free"),
            ]

            ForEach(features, id: \.title) { feat in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feat.icon)
                        .font(.body)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feat.title).font(.subheadline).fontWeight(.semibold)
                        Text(feat.subtitle).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var ctaButton: some View {
        VStack(spacing: 10) {
            if let error = subscriptionStore.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            let product = selectedPlan == .annual
                ? subscriptionStore.annualProduct
                : subscriptionStore.monthlyProduct

            MarquePrimaryButton(
                product != nil
                    ? "Subscribe — \(product!.displayPrice) \(selectedPlan == .annual ? "/ yr" : "/ mo")"
                    : "Subscribe",
                isLoading: false
            ) {
                guard let product else { return }
                Task { await subscriptionStore.purchase(product) }
            }
            .disabled(product == nil)
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text("Subscription renews automatically. Cancel anytime in Settings > Subscriptions.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Its own line, separate from ctaButton's purchaseError above: a
            // failed Restore here is a distinct error from a failed Subscribe.
            if let error = subscriptionStore.restoreError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                Button("Restore Purchases") {
                    Task { await subscriptionStore.restore() }
                }
                .disabled(subscriptionStore.isRestoring)

                Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                Link("Terms", destination: AppLinks.termsOfService)
            }
            .font(.caption2)
            .foregroundColor(.accentColor)
        }
    }

    // The already-Pro state has no renewal line to show, but the policy links
    // must stay reachable from every paywall-adjacent screen.
    private var proLegalLinks: some View {
        HStack(spacing: 16) {
            Link("Privacy Policy", destination: AppLinks.privacyPolicy)
            Link("Terms", destination: AppLinks.termsOfService)
        }
        .font(.caption2)
        .foregroundColor(.accentColor)
    }
}

// MARK: - Plan Card

private struct PlanCard: View {
    let price: String
    let period: String
    let badge: String?
    let detail: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(price).font(.title).fontWeight(.bold)
                    Text(period).font(.subheadline).foregroundColor(.secondary)
                }
                Text(detail).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            if let badge {
                Text(badge)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
