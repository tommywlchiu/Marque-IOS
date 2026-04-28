import SwiftUI

struct SearchResultsView: View {
    @State private var query = ""
    @State private var selectedScope: SearchScope = .cars
    @FocusState private var isSearchFocused: Bool

    private enum SearchScope: String, CaseIterable {
        case cars = "Cars"
        case people = "People"
    }

    // Filtered mock results
    private var filteredCars: [Car] {
        guard !query.isEmpty else { return CarStore.previewCars }
        let q = query.lowercased()
        return CarStore.previewCars.filter {
            $0.make.lowercased().contains(q) ||
            $0.model.lowercased().contains(q) ||
            $0.year.contains(q)
        }
    }

    private var filteredPeople: [AppUser] {
        guard !query.isEmpty else { return AppUser.previewFollowers }
        let q = query.lowercased()
        return AppUser.previewFollowers.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.username.lowercased().contains(q)
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
                emptyResults(for: "No cars matching "\(query)"")
            } else {
                List(filteredCars) { car in
                    NavigationLink(destination: PublicCarDetailView(car: car, owner: .preview)) {
                        CarSearchRow(car: car)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var peopleResults: some View {
        Group {
            if filteredPeople.isEmpty {
                emptyResults(for: "No people matching "\(query)"")
            } else {
                List(filteredPeople) { user in
                    NavigationLink(destination: PublicProfileView(user: user)) {
                        PeopleSearchRow(user: user)
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

// MARK: - Car Search Row

private struct CarSearchRow: View {
    let car: Car

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: "car.fill")
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(car.displayName)
                    .font(.subheadline).fontWeight(.semibold)
                HStack(spacing: 8) {
                    if !car.color.isEmpty { Text(car.color).font(.caption).foregroundColor(.secondary) }
                    if !car.fuelType.isEmpty { Text(car.fuelType).font(.caption).foregroundColor(.secondary) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - People Search Row

private struct PeopleSearchRow: View {
    let user: AppUser

    var body: some View {
        HStack(spacing: 12) {
            UserAvatar(user: user, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.subheadline).fontWeight(.semibold)
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue).font(.caption)
                    }
                }
                Text("@\(user.username)")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SearchResultsView()
    }
}
