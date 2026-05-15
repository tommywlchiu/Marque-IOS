import SwiftUI
import StoreKit

struct ProUpgradeView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var subscriptionStore: SubscriptionStore

    @State private var selectedPlan: PlanOption = .annual

    private enum PlanOption { case monthly, annual }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    planPicker
                    selectedPlanCard
                    featureList
                    ctaButton
                    legalFooter
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
            .navigationTitle("Marque Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                        .foregroundColor(.secondary)
                }
            }
            .task { await subscriptionStore.load() }
            .onChange(of: subscriptionStore.isPro) { _, isPro in
                if isPro { dismiss() }
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
                Image(systemName: "star.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 6) {
                Text("Unlock Everything")
                    .font(.title2).fontWeight(.bold)
                Text("Manage unlimited cars, get early access to new features, and remove all limits.")
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

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Everything in Pro")
                .font(.headline)

            let features: [(icon: String, title: String, subtitle: String)] = [
                ("infinity",         "Unlimited Cars",     "Free plan is limited to 3 vehicles"),
                ("bell.badge.fill",  "Smart Alerts",       "Customizable expiry & maintenance reminders"),
                ("chart.bar.fill",   "Expense Analytics",  "Full breakdown by category and time period"),
                ("person.2.fill",    "Social Profile",     "Share your garage and follow other enthusiasts"),
                ("sparkles",         "Early Access",       "Be first to try new features"),
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
