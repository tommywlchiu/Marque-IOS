import SwiftUI

/// "Popular now" row: up to 6 (make, model) groups drawn from the cars
/// currently loaded in the feed with 2+ public cars, shown under the
/// category chips. Hidden entirely when no group qualifies -- expected
/// with a small seed dataset (see `ExploreView`).
///
/// Tapping a chip narrows the feed in place to that model via a
/// temporary filter (`ExploreView.modelFilter`) rather than navigating
/// into Search: it's a single tap, keeps the user on the feed they're
/// already scrolling, and mirrors the interaction they just used on the
/// category chips directly above this row. `ActiveModelFilterChip` below
/// is what replaces this row once a model is selected, so clearing it is
/// just as cheap.
struct PopularModelsRow: View {
    let groups: [CarTaxonomy.PopularModelGroup]
    let onSelect: (CarTaxonomy.PopularModelGroup) -> Void

    var body: some View {
        if !groups.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(groups) { group in
                        Button {
                            onSelect(group)
                        } label: {
                            Text("🔥 \(group.model) · \(group.count)")
                                .font(.subheadline).fontWeight(.medium)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// Single active model-filter chip ("✕ GT-R") shown in place of
/// `PopularModelsRow` once a model has been tapped. Tapping it clears the
/// filter, which brings the popular row back on the next body evaluation.
struct ActiveModelFilterChip: View {
    let group: CarTaxonomy.PopularModelGroup
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClear) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                    Text(group.model)
                        .font(.subheadline).fontWeight(.semibold)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear \(group.model) filter")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}
