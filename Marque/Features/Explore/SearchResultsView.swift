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
        // Searching makes and @usernames: no capitalized first letter, and no
        // autocorrect turning "kdn" into a word.
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { remember(query) }
        .searchScopes($selectedScope) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .onAppear {
            isSearchFocused = true
            recents = Self.loadRecents()
        }
    }

    // MARK: - Subviews

    private var scopePicker: some View {
        EmptyView() // Handled by searchScopes modifier above
    }

    // MARK: - Suggestions (empty query)

    private static let recentsKey = "marque_recent_searches"
    private static let maxRecents = 6
    @State private var recents: [String] = []

    private static func loadRecents() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    private func remember(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return }
        recents.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        recents.insert(t, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
    }

    private func clearRecents() {
        recents = []
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
    }

    /// Makes with public cars, most cars first.
    private var popularMakes: [String] {
        var counts: [String: (name: String, n: Int)] = [:]
        for car in visibleCars where !car.make.isEmpty {
            let key = CarTaxonomy.squash(car.make)
            counts[key, default: (car.make, 0)].n += 1
        }
        return counts.values.sorted { ($0.n, $1.name) > ($1.n, $0.name) }.prefix(8).map(\.name)
    }

    private var popularModels: [String] {
        CarTaxonomy.popularModelGroups(from: visibleCars, minCount: 1, limit: 6).map { "\($0.make) \($0.model)" }
    }

    private var recentSearchesPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !recents.isEmpty && selectedScope == .cars {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Recent").font(.title3.weight(.bold))
                            Spacer()
                            Button("Clear", action: clearRecents).font(.subheadline)
                        }
                        ForEach(recents, id: \.self) { term in
                            Button { query = term } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath").foregroundColor(.secondary)
                                    Text(term).foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if selectedScope == .cars {
                    if !popularMakes.isEmpty { chipSection("Makes", terms: popularMakes) }
                    if !popularModels.isEmpty { chipSection("Models", terms: popularModels) }
                } else {
                    Text("Search for a username")
                        .font(.subheadline).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
                if selectedScope == .cars && popularMakes.isEmpty && recents.isEmpty {
                    Text("Search for cars, makes, or people")
                        .font(.subheadline).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(16)
        }
    }

    private func chipSection(_ title: String, terms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(terms, id: \.self) { term in
                        Button { query = term; remember(term) } label: {
                            Text(term)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
                    ExploreNoPhotoPlaceholder(make: car.make, model: car.model, car: car, iconSize: 20, showsLabel: false)
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
