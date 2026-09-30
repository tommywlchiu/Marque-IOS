import SwiftUI

/// Combinable filter state for the Explore feed's Filters sheet
/// (`ExploreFiltersSheet`). Session-only (no persistence) -- held as
/// `@State` on `ExploreView` and reset when the tab/app relaunches.
/// Semantics: OR within a group (e.g. Make: BMW OR Audi), AND across groups
/// (Make AND Body Style AND ...), AND with whatever `ExploreView` already
/// applied (the selected category chip, and any "popular now" model chip) --
/// `ExploreView` calls `apply` after both of those, never before.
struct ExploreFilters: Equatable {
    var makes: Set<String> = []
    var bodyStyles: Set<CarTaxonomy.BodyStyleCategory> = []
    var eras: Set<CarTaxonomy.EraCategory> = []
    var powertrains: Set<CarTaxonomy.PowertrainCategory> = []
    var modifiedOnly = false
    var withPhotosOnly = false

    var isEmpty: Bool {
        makes.isEmpty && bodyStyles.isEmpty && eras.isEmpty && powertrains.isEmpty
            && !modifiedOnly && !withPhotosOnly
    }

    /// Number of active *filter groups*, not individual selected values --
    /// selecting both "BMW" and "Audi" in Make still counts as 1, matching
    /// the Filters button badge reading as "N groups engaged".
    var activeCount: Int {
        [!makes.isEmpty, !bodyStyles.isEmpty, !eras.isEmpty, !powertrains.isEmpty, modifiedOnly, withPhotosOnly]
            .filter { $0 }.count
    }

    /// AND across groups, OR within a group. Order (make -> body style ->
    /// era -> powertrain -> toggles) only affects which check short-circuits
    /// first, not the result.
    func apply(_ cars: [PublicCar]) -> [PublicCar] {
        guard !isEmpty else { return cars }
        return cars.filter { car in
            if !makes.isEmpty, !makes.contains(CarTaxonomy.makeGroupKey(car.make)) {
                return false
            }
            if !bodyStyles.isEmpty, !bodyStyles.contains(where: { $0.matches(car.bodyStyle) }) {
                return false
            }
            if !eras.isEmpty, !eras.contains(where: { $0.matches(year: car.year) }) {
                return false
            }
            if !powertrains.isEmpty {
                guard let p = CarTaxonomy.powertrainCategory(fuelType: car.fuelType), powertrains.contains(p) else {
                    return false
                }
            }
            if modifiedOnly && !car.isModified { return false }
            if withPhotosOnly && car.galleryURLs.isEmpty { return false }
            return true
        }
    }
}

// MARK: - Sheet

/// Presented from `ExploreView`'s Filters button as
/// `.sheet(isPresented:) { ExploreFiltersSheet(cars:filters:) }`.
struct ExploreFiltersSheet: View {
    /// `ExploreView`'s category-filtered feed (the currently selected chip,
    /// e.g. "JDM", already applied) -- so both the Make chip options and
    /// the live "Show N cars" count reflect exactly what these filters
    /// would add on top of the chip, not the whole unfiltered feed.
    let cars: [PublicCar]
    @Binding var filters: ExploreFilters
    @Environment(\.dismiss) private var dismiss

    /// Edited independently of the live `filters` binding so a
    /// swipe-to-dismiss (no explicit Cancel button needed) discards
    /// in-progress changes; only "Show N Cars" writes back.
    @State private var draft: ExploreFilters
    @State private var showingAllMakes = false

    init(cars: [PublicCar], filters: Binding<ExploreFilters>) {
        self.cars = cars
        self._filters = filters
        self._draft = State(initialValue: filters.wrappedValue)
    }

    private var makeGroups: [CarTaxonomy.MakeGroup] {
        CarTaxonomy.makeGroups(from: cars)
    }

    private var visibleMakeGroups: [CarTaxonomy.MakeGroup] {
        showingAllMakes ? makeGroups : Array(makeGroups.prefix(12))
    }

    private var resultCount: Int { draft.apply(cars).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    makeSection
                    chipSection(title: "Body Style", options: CarTaxonomy.BodyStyleCategory.allCases, selection: $draft.bodyStyles) { $0.rawValue }
                    chipSection(title: "Era", options: CarTaxonomy.EraCategory.allCases, selection: $draft.eras) { $0.rawValue }
                    chipSection(title: "Powertrain", options: CarTaxonomy.PowertrainCategory.allCases, selection: $draft.powertrains) { $0.rawValue }
                    toggleSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 90) // clears the bottom bar
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    @ViewBuilder
    private var makeSection: some View {
        if !makeGroups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MarqueSectionHeader(title: "Make")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                    ForEach(visibleMakeGroups) { group in
                        FilterChip(title: group.displayName, isSelected: draft.makes.contains(group.id)) {
                            toggle(group.id, in: &draft.makes)
                        }
                    }
                }
                if makeGroups.count > 12 {
                    Button(showingAllMakes ? "Show Less" : "Show All (\(makeGroups.count))") {
                        withAnimation(.spring(duration: 0.2)) { showingAllMakes.toggle() }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    /// Shared layout for the three fixed-option chip groups (Body Style,
    /// Era, Powertrain) -- only the option list, selection binding and
    /// title differ between them.
    private func chipSection<Option: Hashable & CaseIterable>(
        title: String,
        options: Option.AllCases,
        selection: Binding<Set<Option>>,
        label: @escaping (Option) -> String
    ) -> some View where Option.AllCases: RandomAccessCollection, Option: Identifiable {
        VStack(alignment: .leading, spacing: 10) {
            MarqueSectionHeader(title: title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                ForEach(options) { option in
                    FilterChip(title: label(option), isSelected: selection.wrappedValue.contains(option)) {
                        toggle(option, in: &selection.wrappedValue)
                    }
                }
            }
        }
    }

    private var toggleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            MarqueSectionHeader(title: "More")
            Toggle("Modified only", isOn: $draft.modifiedOnly)
                .padding(.vertical, 6)
            Divider()
            Toggle("With photos only", isOn: $draft.withPhotosOnly)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button("Reset") { draft = ExploreFilters() }
                    .disabled(draft.isEmpty)
                    .buttonStyle(.bordered)

                Button {
                    filters = draft
                    dismiss()
                } label: {
                    Text("Show \(resultCount) Car\(resultCount == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(isSelected ? 0 : 0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Self-check

#if DEBUG
extension ExploreFilters {
    /// See `CarTaxonomy._selfCheck` for the same pattern/rationale (no
    /// XCTest target exists -- CLAUDE.md). Not invoked automatically.
    static func _selfCheck() {
        let cars: [PublicCar] = [
            .previewStub(make: "Nissan", model: "GT-R", bodyStyle: "Coupe", year: "2020", fuelType: "Gasoline", modified: true, hasPhoto: true),
            .previewStub(make: "Tesla", model: "Model 3", bodyStyle: "Sedan", year: "2022", fuelType: "Electric", modified: false, hasPhoto: true),
            .previewStub(make: "Ford", model: "Bronco", bodyStyle: "Sport Utility Vehicle (SUV)", year: "1985", fuelType: "Gasoline", modified: false, hasPhoto: false),
        ]

        var f = ExploreFilters()
        assert(f.isEmpty && f.activeCount == 0)
        assert(f.apply(cars).count == cars.count) // empty filters pass everything through

        f.bodyStyles = [.coupe]
        assert(f.activeCount == 1)
        assert(f.apply(cars).map(\.make) == ["Nissan"])

        f.powertrains = [.electric]
        assert(f.activeCount == 2)
        assert(f.apply(cars).isEmpty) // AND across groups: no car is both a coupe and electric

        f = ExploreFilters()
        f.eras = [.classic]
        f.withPhotosOnly = true
        assert(f.apply(cars).isEmpty) // the 1985 SUV is classic but has no photo

        f = ExploreFilters()
        f.modifiedOnly = true
        assert(f.apply(cars).map(\.make) == ["Nissan"])
    }
}

private extension PublicCar {
    /// Extends `CarTaxonomy`'s own `previewStub` with the extra fields this
    /// file's self-check needs (bodyStyle, fuelType, mods, photos).
    static func previewStub(make: String, model: String, bodyStyle: String, year: String, fuelType: String, modified: Bool, hasPhoto: Bool) -> PublicCar {
        let json: [String: Any] = [
            "carId": UUID().uuidString,
            "ownerUID": "u", "ownerUsername": "u",
            "make": make, "model": model, "year": year,
            "color": "", "mileage": "", "trim": "", "bodyStyle": bodyStyle,
            "driveType": "", "engine": "", "fuelType": fuelType, "transmission": "",
            "notes": "", "photoOffsetY": 0.0, "serviceHistory": [],
            "mods": modified ? [["category": "exterior", "name": "Test Mod", "brand": NSNull()]] : [],
            "photoURLs": hasPhoto ? ["https://example.com/photo.jpg"] : [],
            "likeCount": 0, "weeklyLikeCount": 0, "commentCount": 0,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(PublicCar.self, from: data)
    }
}
#endif
