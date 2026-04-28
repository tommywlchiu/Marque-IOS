import SwiftUI

struct ProUpgradeView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlan: Plan = .annual
    @State private var isPurchasing = false

    private enum Plan: String, CaseIterable {
        case monthly = "Monthly"
        case annual = "Annual"
    }

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
            ForEach(Plan.allCases, id: \.self) { plan in
                Text(plan.rawValue).tag(plan)
            }
        }
        .pickerStyle(.segmented)
    }

    private var selectedPlanCard: some View {
        VStack(spacing: 8) {
            switch selectedPlan {
            case .monthly:
                PlanCard(
                    price: "$2.99",
                    period: "/ month",
                    badge: nil,
                    detail: "Billed monthly. Cancel anytime."
                )
            case .annual:
                PlanCard(
                    price: "$24.99",
                    period: "/ year",
                    badge: "Save 30%",
                    detail: "That's just $2.08 / month. Cancel anytime."
                )
            }
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Everything in Pro")
                .font(.headline)

            let features: [(icon: String, title: String, subtitle: String)] = [
                ("infinity", "Unlimited Cars", "Free plan is limited to 3 vehicles"),
                ("bell.badge.fill", "Smart Alerts", "Customizable expiry & maintenance reminders"),
                ("chart.bar.fill", "Expense Analytics", "Full breakdown by category and time period"),
                ("person.2.fill", "Social Profile", "Share your garage and follow other enthusiasts"),
                ("sparkles", "Early Access", "Be first to try new features"),
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
        MarquePrimaryButton(
            selectedPlan == .annual ? "Start Free Trial — $24.99 / yr" : "Start Free Trial — $2.99 / mo",
            isLoading: isPurchasing
        ) {
            purchase()
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text("7-day free trial, then charged automatically. Cancel anytime in Settings > Subscriptions.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Restore Purchases") { /* StoreKit restore */ }
                Button("Privacy Policy") { }
                Button("Terms") { }
            }
            .font(.caption2)
            .foregroundColor(.accentColor)
        }
    }

    // MARK: - Actions

    private func purchase() {
        isPurchasing = true
        // Wire up StoreKit purchase here
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            isPurchasing = false
            dismiss()
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
                    Text(price)
                        .font(.title).fontWeight(.bold)
                    Text(period)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let badge {
                Text(badge)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    ProUpgradeView()
}
