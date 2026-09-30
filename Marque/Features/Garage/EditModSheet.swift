import SwiftUI

/// Add/edit sheet for a single `CarMod`. `mod == nil` is add mode; a non-nil
/// `mod` is edit mode (adds a Delete section). Always re-reads the live car
/// from `CarStore` at save/delete time rather than trusting the `car` it was
/// constructed with, so a save made after another edit landed (e.g. a second
/// device) still applies against current data — `CarStore.addMod`/`updateMod`/
/// `deleteMod` all copy the car they're given.
struct EditModSheet: View {
    let car: Car
    let mod: CarMod?

    @EnvironmentObject private var carStore: CarStore
    @Environment(\.dismiss) private var dismiss

    @State private var category: ModCategory = .other
    @State private var name = ""
    @State private var brand = ""
    @State private var hasInstallDate = false
    @State private var installedAt = Date()
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool { mod != nil }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        MarqueErrorBanner(message: errorMessage)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section(header: Text("Category")) {
                    categoryGrid
                }

                Section(header: Text("Name"), footer: Text("\(name.count)/\(CarMod.maxNameLength) characters")) {
                    TextField("e.g. Akrapovič Evolution exhaust", text: $name)
                        .onChange(of: name) { _, newValue in
                            if newValue.count > CarMod.maxNameLength {
                                name = String(newValue.prefix(CarMod.maxNameLength))
                            }
                        }
                }

                Section(header: Text("Brand"), footer: Text("\(brand.count)/\(CarMod.maxBrandLength) characters")) {
                    TextField("Optional", text: $brand)
                        .onChange(of: brand) { _, newValue in
                            if newValue.count > CarMod.maxBrandLength {
                                brand = String(newValue.prefix(CarMod.maxBrandLength))
                            }
                        }
                }

                Section {
                    Toggle("Install Date", isOn: $hasInstallDate.animation())
                    if hasInstallDate {
                        DatePicker("Installed", selection: $installedAt, displayedComponents: .date)
                    }
                }

                Section(
                    header: Text("Notes"),
                    footer: Text("Private — only you can see this. \(notes.count)/\(CarMod.maxNotesLength) characters")
                ) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .onChange(of: notes) { _, newValue in
                            if newValue.count > CarMod.maxNotesLength {
                                notes = String(newValue.prefix(CarMod.maxNotesLength))
                            }
                        }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Mod", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Mod" : "Add Mod")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Delete Mod", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteMod() }
            } message: {
                Text("This will permanently delete this mod. This cannot be undone.")
            }
            .onAppear { populate() }
        }
    }

    // MARK: - Category grid

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
            ForEach(ModCategory.allCases) { cat in
                ModCategoryChip(category: cat, isSelected: category == cat) {
                    category = cat
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Populate / Save / Delete

    private func populate() {
        guard let mod else { return }
        category = mod.category
        name = mod.name
        brand = mod.brand ?? ""
        if let installed = mod.installedAt {
            hasInstallDate = true
            installedAt = installed
        }
        notes = mod.notes ?? ""
    }

    private func save() {
        errorMessage = nil
        guard let currentCar = carStore.cars.first(where: { $0.id == car.id }) else {
            errorMessage = "This car could not be found."
            return
        }

        var updated = mod ?? CarMod()
        updated.category = category
        updated.name = name
        updated.brand = brand
        updated.installedAt = hasInstallDate ? installedAt : nil
        updated.notes = notes

        do {
            if mod == nil {
                try carStore.addMod(updated, to: currentCar)
            } else {
                try carStore.updateMod(updated, in: currentCar)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch let error as CarStore.ModError {
            errorMessage = friendlyMessage(for: error)
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
    }

    private func deleteMod() {
        guard let mod, let currentCar = carStore.cars.first(where: { $0.id == car.id }) else { return }
        carStore.deleteMod(mod, from: currentCar)
        dismiss()
    }

    private func friendlyMessage(for error: CarStore.ModError) -> String {
        switch error {
        case .nameRequired: return "Give this mod a name."
        case .notAllowed: return "Let's keep it friendly. Please rephrase."
        case .limitReached: return "You've reached 30 mods."
        case .notFound: return "That mod could not be found. It may have been deleted."
        }
    }
}

// MARK: - Category chip

private struct ModCategoryChip: View {
    let category: ModCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: ModIcon.symbolName(for: category))
                    .font(.title3)
                Text(category.displayName)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
