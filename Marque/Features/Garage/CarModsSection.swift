import SwiftUI

/// Owner's "Mods" section on their car page: add, edit, delete and
/// drag-to-reorder modifications. Self-contained (owns its own presenters),
/// same pattern as `CarValueSection`/`EngineSoundOwnerSection` — lives inside
/// `CarDetailView`'s List, taking the live `Car` directly rather than a
/// `Binding` so it always reflects `CarStore`'s current copy.
struct CarModsSection: View {
    let car: Car

    @EnvironmentObject private var carStore: CarStore
    @State private var showingAddMod = false
    @State private var editingMod: CarMod?
    /// Scopes SwiftUI's edit mode to just this section's `ForEach` (via the
    /// `.environment` below) so drag-to-reorder handles appear here without
    /// putting the rest of the List — Registration, Insurance, etc. — into
    /// edit mode too.
    @State private var isReordering = false

    private var mods: [CarMod] { car.mods }

    var body: some View {
        Section(header: header) {
            if mods.isEmpty {
                Button {
                    showingAddMod = true
                } label: {
                    Label("Show off your build: add your first mod", systemImage: "wrench.and.screwdriver")
                        .foregroundColor(.accentColor)
                }
            } else {
                ForEach(mods) { mod in
                    Button {
                        editingMod = mod
                    } label: {
                        ModRow(mod: mod)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double-tap to edit")
                }
                .onMove { offsets, destination in
                    var reordered = mods
                    reordered.move(fromOffsets: offsets, toOffset: destination)
                    carStore.reorderMods(reordered, in: car)
                }
            }
        }
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        .sheet(isPresented: $showingAddMod) {
            EditModSheet(car: car, mod: nil)
        }
        .sheet(item: $editingMod) { mod in
            EditModSheet(car: car, mod: mod)
        }
    }

    private var header: some View {
        HStack {
            Text(mods.isEmpty ? "Mods" : "Mods · \(mods.count)")
            Spacer()
            if mods.count > 1 {
                Button(isReordering ? "Done" : "Reorder") {
                    withAnimation { isReordering.toggle() }
                }
                .font(.subheadline)
            }
            Button {
                showingAddMod = true
            } label: {
                Image(systemName: "plus.circle.fill").font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add mod")
        }
    }
}

// MARK: - Row

private struct ModRow: View {
    let mod: CarMod

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ModIcon.symbolName(for: mod.category))
                .font(.body)
                .foregroundColor(.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name)
                    .foregroundColor(.primary)
                if let brand = mod.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let date = mod.installedAt {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.4))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ModIcon.accessibilityLabel(for: mod.category, name: mod.name, brand: mod.brand))
    }
}

// MARK: - Icon validation
//
// `ModCategory.symbolName` is documented as cosmetic-only, unverified against
// the SF Symbols catalog. Falls back to a known-good symbol at runtime rather
// than risk a blank glyph. Shared with `PublicCarModsSection`
// (Features/Social/CarDetailSocial.swift) and `ModCategoryChip`
// (EditModSheet.swift) so the fallback and the accessibility-label format
// only live in one place.
enum ModIcon {
    static let fallbackSymbolName = "wrench.and.screwdriver"

    static func symbolName(for category: ModCategory) -> String {
        UIImage(systemName: category.symbolName) != nil ? category.symbolName : fallbackSymbolName
    }

    /// "Exhaust: Akrapovič Evolution by Akrapovič" (brand omitted if absent).
    static func accessibilityLabel(for category: ModCategory, name: String, brand: String?) -> String {
        var label = "\(category.displayName): \(name)"
        if let brand, !brand.isEmpty {
            label += " by \(brand)"
        }
        return label
    }
}
