import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject var exploreStore: ExploreStore
    // Injected ambiently from the root (Marque.swift) -- ExploreView doesn't need
    // to attach it explicitly for this pushed destination to see it.
    @EnvironmentObject var blockStore: BlockStore
    @State private var query = ""
    @State private var selectedScope: SearchScope = .cars
    @FocusState private var isSearchFocused: Bool

    private enum SearchScope: String, CaseIterable {
        case cars = "Cars"
        case people = "People"
    }

    // Blocked-user filtering applied at the base of both derived result lists,
    // matching ExploreView's `visibleCars` pattern, so a blocked user's cars and
    // profile never surface in either search scope.
    private var visibleCars: [PublicCar] {
        blockStore.filter(exploreStore.cars, ownerUID: \.ownerUID)
    }

    /// Model-aware car search, ranked exact-model-match first, then
    /// make match, then other text matches (`CarTaxonomy.matchTier`).
    /// Intentionally bypasses `ExploreStore.results(matching:)` (plain
    /// text `contains`) in favor of `CarTaxonomy`, which understands
    /// punctuation-insensitive model text ("gtr"/"GT-R"/"gt r") and the
    /// nickname alias table (R35, Vette, Lambo, ...). "Supercars" as a
    /// literal search term returns the Supercars set instead of going
    /// through ranking.
    private var filteredCars: [PublicCar] {
        guard !query.isEmpty else { return visibleCars }

        if CarTaxonomy.supercarsSearchTerms.contains(CarTaxonomy.squash(query)) {
            return visibleCars.filter { CarTaxonomy.isSupercar(make: $0.make, model: $0.model, trim: $0.trim) }
        }

        if CarTaxonomy.modifiedSearchTerms.contains(CarTaxonomy.squash(query)) {
            return visibleCars.filter { $0.isModified }
        }

        // `sorted` is stable (Swift 5+), so cars tied on tier keep
        // `visibleCars`' existing order.
        return visibleCars
            .compactMap { car -> (car: PublicCar, tier: CarTaxonomy.SearchMatchTier)? in
                guard let tier = CarTaxonomy.matchTier(
                    query: query,
                    make: car.make, model: car.model, trim: car.trim,
                    year: car.year, ownerUsername: car.ownerUsername,
                    mods: car.mods.map { (name: $0.name, brand: $0.brand) }
                ) else { return nil }
                return (car, tier)
            }
            .sorted { $0.tier < $1.tier }
            .map(\.car)
    }

    private var filteredPeople: [PublicCar] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return visibleCars.filter { $0.ownerUsername.lowercased().contains(q) }
    }

    // Deduplicated owners for the People tab
    private var uniqueOwners: [(uid: String, username: String)] {
        var seen = Set<String>()
        return filteredPeople.compactMap { car in
            guard !seen.contains(car.ownerUID) else { return nil }
            seen.insert(car.ownerUID)
            return (uid: car.ownerUID, username: car.ownerUsername)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            scopePicker

            if query.isEmpty {
                recentSearchesPlaceholder
            } else {
                resultsList
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cars, makes, or people…")
        .searchScopes($selectedScope) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .onAppear { isSearchFocused = true }
    }

    // MARK: - Subviews

    private var scopePicker: some View {
        EmptyView() // Handled by searchScopes modifier above
    }

    private var recentSearchesPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))
            Text("Search for cars, makes, or people")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        switch selectedScope {
        case .cars: carResults
        case .people: peopleResults
        }
    }

    private var carResults: some View {
        Group {
            if filteredCars.isEmpty {
                emptyResults(for: query.isEmpty ? "No public cars yet" : "No cars matching \"\(query)\"")
            } else {
                List(filteredCars) { car in
                    NavigationLink(destination: CarDetailView(publicCar: car)
                        .environmentObject(exploreStore)) {
                        PublicCarSearchRow(car: car)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var peopleResults: some View {
        Group {
            if uniqueOwners.isEmpty {
                emptyResults(for: query.isEmpty ? "Search for a username" : "No people matching \"\(query)\"")
            } else {
                List(uniqueOwners, id: \.uid) { owner in
                    NavigationLink(destination: PublicProfileView(ownerUID: owner.uid, ownerUsername: owner.username)
                        .environmentObject(exploreStore)) {
                        OwnerSearchRow(username: owner.username)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func emptyResults(for message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Search Rows

private struct PublicCarSearchRow: View {
    let car: PublicCar

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url = car.primaryPhotoURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(car.displayName).font(.subheadline).fontWeight(.semibold)
                HStack(spacing: 8) {
                    if !car.color.isEmpty {
                        Text(car.color).font(.caption).foregroundColor(.secondary)
                    }
                    Text("@\(car.ownerUsername)").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor.opacity(0.1))
            .overlay(Image(systemName: "car.fill").foregroundColor(.accentColor))
    }
}

private struct OwnerSearchRow: View {
    let username: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(username.prefix(1).uppercased())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.accentColor)
                )
            Text("@\(username)").font(.subheadline).fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }
}
