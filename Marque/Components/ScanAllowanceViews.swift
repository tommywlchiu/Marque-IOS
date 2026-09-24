//
//  ScanAllowanceViews.swift
//  Marque-Prototype
//
//  FR-14.4 UI shared by every document-scan entry point (license, insurance
//  card, receipt): the remaining-allowance caption and the paywall shown when
//  the allowance is spent. Both read ScanAllowanceStore / SubscriptionStore from
//  the environment so call sites stay a few lines each.
//

import SwiftUI

/// "3 of 5 scans left today". Sits in the trailing edge of a scan row so the
/// allowance is visible before the tap, not surfaced as a failure afterward.
struct ScanAllowanceCaption: View {
    @EnvironmentObject private var scanAllowance: ScanAllowanceStore

    var body: some View {
        // Hidden while the server plan is unknown: a guessed number is worse than none.
        if let remaining = scanAllowance.remaining, let limit = scanAllowance.limit {
            Text(remaining == 0
                 ? "No scans left today"
                 : "\(remaining) of \(limit) scans left today")
                .font(.caption)
                .foregroundColor(remaining == 0 ? .orange : .secondary)
        }
    }
}

private struct ScanCapPaywallModifier: ViewModifier {
    @Binding var isPresented: Bool
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ProUpgradeView(trigger: .scanCap)
                .environmentObject(subscriptionStore)
        }
    }
}

extension View {
    /// Presents the Pro upsell (`paywall_viewed.trigger = scan_cap`) when a scan
    /// entry point finds the day's allowance spent.
    func scanCapPaywall(isPresented: Binding<Bool>) -> some View {
        modifier(ScanCapPaywallModifier(isPresented: isPresented))
    }
}
