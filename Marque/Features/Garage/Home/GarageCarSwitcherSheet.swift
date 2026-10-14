import SwiftUI

/// The vehicle switcher behind the Garage header's name + chevron: every car,
/// plus "Add a Car". Add a Car doesn't present anything itself: it closes the
/// switcher and tells the Garage, which applies the free-car-limit gate
/// (`CarStore.freeCarLimit` unless `SubscriptionStore.isPro` → paywall,
/// otherwise `AddCarView`) once this sheet is gone. A sheet opened from inside
/// this one closed again right after appearing, taking the paywall with it.
struct GarageCarSwitcherSheet: View {
    let selectedCarID: UUID?
    let onSelect: (UUID) -> Void
    let onAddCar: () -> Void

    @EnvironmentObject private var carStore: CarStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(carStore.cars) { car in
                        Button {
                            onSelect(car.id)
                            dismiss()
                        } label: {
                            CarSwitcherRow(car: car, isSelected: car.id == selectedCarID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(car.id == selectedCarID ? .isSelected : [])
                    }

                    Button {
                        onAddCar()
                        dismiss()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "plus")
                                .font(.title3.weight(.medium))
                                .foregroundColor(GarageTheme.icon)
                                .frame(width: 72, height: 48)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                            Text("Add a Car")
                                .font(.headline)
                                .foregroundColor(GarageTheme.primaryText)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
            .background(GarageTheme.background.ignoresSafeArea())
            .navigationTitle("Your Cars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GarageTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium, .large])
        .presentationBackground(GarageTheme.background)
    }
}

private struct CarSwitcherRow: View {
    let car: Car
    let isSelected: Bool
    /// The studio render (`CarRenderLibrary`, frame 0) for a car without a
    /// cover photo, when the catalog covers it.
    @State private var render: UIImage?

    private var subtitle: String {
        [GarageSummary.mileageText(car), car.licensePlate.isEmpty ? nil : car.licensePlate]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 16) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(car.displayName)
                    .font(.headline)
                    .foregroundColor(GarageTheme.primaryText)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(GarageTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(GarageTheme.primaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .task(id: [car.make, car.model, car.year, car.color].joined(separator: "|")) {
            guard car.primaryPhotoFileName == nil else { return }
            if let cached = CarRenderLibrary.cachedStill(for: car) {
                render = cached
            } else {
                render = await CarRenderLibrary.still(for: car)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let fileName = car.primaryPhotoFileName {
            CarPhotoImage(fileName: fileName, storageURL: car.primaryPhotoStorageURL)
                .frame(width: 72, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let render {
            Image(uiImage: render)
                .resizable()
                .scaledToFit()
                .padding(4)
                .frame(width: 72, height: 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        } else {
            Image(systemName: "car.side.fill")
                .font(.title3)
                .foregroundColor(GarageTheme.tertiaryText)
                .frame(width: 72, height: 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        }
    }
}
