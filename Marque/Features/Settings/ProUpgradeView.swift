import SwiftUI
import StoreKit
import AVFoundation

struct ProUpgradeView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var subscriptionStore: SubscriptionStore

    // FR-11.5: which gate brought the user here. Deliberately has no default —
    // a default would let a call site silently mislabel its own trigger.
    let trigger: AnalyticsService.PaywallTrigger

    @State private var selectedPlan: PlanOption = .annual

    // Set true right before calling subscriptionStore.purchase(product) and
    // false once it returns (see ctaButton). Doubles as the "did the isPro /
    // isFamilyShared flip below come from this screen's own purchase tap"
    // gate: purchase() awaits refreshProStatus() before returning, so the
    // @Published flip lands on MainActor while this is still true. A flip
    // that arrives with this false (Transaction.updates firing in the
    // background, or restore() completing) keeps the old silent-dismiss
    // behavior instead of celebrating.
    @State private var isPurchasing = false
    @State private var showCelebration = false

    private enum PlanOption { case monthly, annual }

    var body: some View {
        NavigationStack {
            Group {
                if showCelebration {
                    ProCelebrationView(isFamilyShared: subscriptionStore.isFamilyShared) {
                        dismiss()
                    }
                } else {
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
                }
            }
            .navigationTitle("Marque Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Hidden during the celebration so the user acknowledges via
                // its own "Let's Go" button rather than this Done/Not Now one.
                if !showCelebration {
                    ToolbarItem(placement: .cancellationAction) {
                        // "Done" only for a fully-resolved Pro user with nothing left to
                        // do here; a Family Sharing member still has a live CTA, so they
                        // get "Not Now" like a non-Pro user.
                        Button(subscriptionStore.isPro && !subscriptionStore.isFamilyShared ? "Done" : "Not Now") { dismiss() }
                            .foregroundColor(.secondary)
                    }
                    // FR-08.5: Restore Purchases must be reachable without
                    // scrolling. The footer button (legalFooter) already
                    // covers the purchase paths once scrolled to, but this
                    // toolbar button makes it visible immediately on open.
                    // The already-Pro section has its own Restore button
                    // (alreadyProSection) directly in its no-scroll layout,
                    // so it's excluded here to avoid a redundant control.
                    if !(subscriptionStore.isPro && !subscriptionStore.isFamilyShared) {
                        // .topBarTrailing rather than .confirmationAction — this
                        // isn't the screen's primary action (Subscribe is), so it
                        // shouldn't pick up confirmationAction's bold "main CTA" styling.
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Restore") {
                                Task { await subscriptionStore.restore() }
                            }
                            .disabled(subscriptionStore.isRestoring)
                        }
                    }
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
                guard isPro else { return }
                if isPurchasing {
                    showCelebration = true
                } else {
                    dismiss()
                }
            }
            // A Family Sharing member who then buys their own subscription stays
            // isPro == true throughout, so the onChange above never fires for them.
            // isFamilyShared flipping true -> false is the actual "just converted"
            // signal (refreshProStatus sets it false once a direct purchase exists).
            .onChange(of: subscriptionStore.isFamilyShared) { wasFamilyShared, isFamilyShared in
                guard wasFamilyShared && !isFamilyShared else { return }
                if isPurchasing {
                    showCelebration = true
                } else {
                    dismiss()
                }
            }
        }
        // Opened from the Garage, which forces dark mode on its content
        // (`.environment(\.colorScheme, .dark)`), the text went white while
        // the sheet itself kept the system's light background — white on
        // white. An explicit adaptive background follows the same scheme as
        // the text: dark from the Garage, the system's own elsewhere.
        .presentationBackground(Color(.systemBackground))
    }

    // MARK: - Sections

    private var heroTitle: String {
        trigger == .carLimit ? "Room for Every Car" : "More from Marque Assistant"
    }

    private var heroSubtitle: String {
        trigger == .carLimit
            ? "The free plan holds \(CarStore.freeCarLimit) cars. Pro adds as many as you own, plus 50x the Assistant messages and a Pro badge on your profile."
            : "50x the daily messages, plus unlimited cars and a Pro badge on your profile."
    }

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
            // "unlock everything" framing FR-08.7 was written to retire —
            // except when the user hit the car limit (owner decision,
            // 2026-10-06): there the headline answers what they just tried.
            VStack(spacing: 6) {
                Text(heroTitle)
                    .font(.title2).fontWeight(.bold)
                Text(heroSubtitle)
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
                ("infinity",                          "Unlimited Cars",   "Free plan is limited to \(CarStore.freeCarLimit) vehicles"),
                ("checkmark.seal.fill",               "Pro Badge",        "Shown next to your name in Garage, Settings and Explore"),
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
                isLoading: isPurchasing
            ) {
                guard let product else { return }
                isPurchasing = true
                Task {
                    defer { isPurchasing = false }
                    await subscriptionStore.purchase(product)
                }
            }
            .disabled(product == nil || isPurchasing)
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

// MARK: - Celebration

// Shown in place of the paywall ScrollView the instant a purchase this
// screen initiated actually completes (see ProUpgradeView.isPurchasing).
// A background entitlement flip (Transaction.updates, or restore()) never
// reaches this — those still take the old silent-dismiss path.
private struct ProCelebrationView: View {
    let isFamilyShared: Bool
    let onContinue: () -> Void

    @State private var badgeVisible = false
    // Held so ARC keeps it alive through playback (assigned in
    // playCelebrationSound(), never read otherwise).
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {
            // Behind the text/button rather than above it — a one-shot burst
            // (see ConfettiPieceView) that settles in ~2s, not a loop, so it
            // never competes with reading the screen.
            ConfettiView()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: "car.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.accentColor)

                    // The badge pops in shortly after the logo appears, with a
                    // spring overshoot rather than a linear fade.
                    ProBadge()
                        .scaleEffect(1.7)
                        .scaleEffect(badgeVisible ? 1 : 0.01)
                        .opacity(badgeVisible ? 1 : 0)
                        .offset(x: 42, y: -42)
                }

                VStack(spacing: 8) {
                    Text("Welcome to Marque Pro!")
                        .font(.title2).fontWeight(.bold)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                Spacer()

                MarquePrimaryButton("Awesome, Thanks!") {
                    onContinue()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.35)) {
                badgeVisible = true
            }
            playCelebrationSound()
        }
    }

    // Setup (audio session + synthesis + playback) lives in the shared
    // CelebrationChime.play() (Components/CelebrationEffects.swift).
    // Fire-and-forget: a nil result (setup or playback failure) must never
    // surface to the user or affect the celebration UI.
    private func playCelebrationSound() {
        audioPlayer = CelebrationChime.play()
    }

    // Pulled straight from featureList / familySharedFeatureList — per
    // FR-08.7 this must never claim a benefit that isn't actually gated,
    // and a Family Sharing member already has Unlimited Cars + the Pro
    // Badge, so their copy only names what subscribing personally added.
    private var subtitle: String {
        isFamilyShared
            ? "You've unlocked 500 Assistant messages a day and \(ScanAllowanceStore.proDailyCap) document scans a day."
            : "You now have 500 Assistant messages a day, \(ScanAllowanceStore.proDailyCap) document scans a day, unlimited cars, and a Pro badge on your profile."
    }
}

// Confetti (ConfettiPiece/ConfettiView/ConfettiPieceView) and CelebrationChime
// now live in Components/CelebrationEffects.swift, shared with other
// milestone celebrations (e.g. AddCarView's onboarding first-car step).
