import SwiftUI

/// Owner's "Estimated Value" section on their car page. The exact value is
/// private and shown only here. The public car can only ever show a rounded
/// range of the car's latest AI estimate (computed server-side from the
/// server's own copy of it), and only while "Show on public profile" is on.
/// A value the owner typed is never shown publicly, so it can't be inflated.
struct CarValueSection: View {
    let car: Car

    @EnvironmentObject private var carStore: CarStore
    @State private var showingEstimate = false
    @State private var showingManualEntry = false

    var body: some View {
        // Presenters hang off the header: it's the one view that exists in
        // both states, so a sheet isn't torn down when the rows swap.
        Section(
            header: Text("Estimated Value").modifier(presenters),
            footer: Text("An estimate, not an appraisal. Your value is private. Only an AI estimate can be shown publicly, as a rounded range.")
        ) {
            if let value = car.estimatedValue {
                Button { showingManualEntry = true } label: { valueRow(value) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double-tap to edit")
                visibilityToggle
                Button { showingEstimate = true } label: {
                    Label("Re-estimate with AI", systemImage: "sparkles")
                }
            } else {
                Button { showingEstimate = true } label: {
                    Label("Estimate with AI", systemImage: "sparkles")
                }
                Button { showingManualEntry = true } label: {
                    Label("Enter Value Manually", systemImage: "dollarsign.circle")
                }
            }
        }
    }

    // Attached to exactly one view (the header): modifiers on a List Section
    // can apply to every row, which would stack duplicate sheets on one binding.
    private var presenters: CarValuePresenters {
        CarValuePresenters(
            carID: car.id,
            showingEstimate: $showingEstimate,
            showingManualEntry: $showingManualEntry
        )
    }

    private func valueRow(_ value: Double) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                Text(sourceCaption)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "pencil.circle.fill")
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var sourceCaption: String {
        let source = car.valueSource == .ai ? "AI estimate" : "Your estimate"
        guard let updated = car.valueUpdatedAt else { return source }
        return "\(source) · Updated \(updated.formatted(date: .abbreviated, time: .omitted))"
    }

    @ViewBuilder
    private var visibilityToggle: some View {
        if carStore.canShowValuePublicly(car) {
            publicToggle
        } else {
            // No applicable AI estimate: nothing can be shown publicly. A typed
            // value never is (it's unverifiable), so offer the estimate instead.
            VStack(alignment: .leading, spacing: 2) {
                Text("Show on public profile")
                    .foregroundColor(.secondary)
                Text(carStore.aiValuation(for: car) == nil
                     ? "Get an AI estimate to show a range publicly. Your own value stays private."
                     : "Details changed since the last AI estimate. Re-estimate to show a range publicly.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var publicToggle: some View {
        Toggle(isOn: Binding(
            get: { car.showValuePublicly },
            set: { show in
                guard let current = carStore.cars.first(where: { $0.id == car.id }) else { return }
                carStore.setValueVisibility(show, for: current)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show on public profile")
                Text(visibilityCaption)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var visibilityCaption: String {
        guard let range = carStore.publicValueRangePreview(for: car) else {
            return "Only you can see this value"
        }
        guard car.showValuePublicly else {
            return "Would show your AI estimate as \u{201C}Est. value \(range)\u{201D}"
        }
        let shown = "Shown as \u{201C}Est. value \(range)\u{201D}"
        return car.isPublic ? shown : shown + " once this car is public"
    }
}

private struct CarValuePresenters: ViewModifier {
    let carID: UUID
    @Binding var showingEstimate: Bool
    @Binding var showingManualEntry: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingEstimate) {
                EstimateValueSheet(carID: carID)
            }
            .sheet(isPresented: $showingManualEntry) {
                EditCarValueSheet(carID: carID)
            }
    }
}

// MARK: - Manual entry

/// Type (or edit, or clear) the value by hand. Saved with source `.owner`.
struct EditCarValueSheet: View {
    let carID: UUID

    @EnvironmentObject private var carStore: CarStore
    @Environment(\.dismiss) private var dismiss
    @State private var valueText = ""
    @FocusState private var focused: Bool

    private var car: Car? { carStore.cars.first(where: { $0.id == carID }) }
    private var parsedValue: Double? { CarValueInput.parse(valueText) }

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Your best guess at what this car would sell for today, in US dollars. Only you can see the exact figure.")) {
                    HStack {
                        Text("$").foregroundColor(.secondary)
                        TextField("Value", text: $valueText)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .accessibilityLabel("Value in US dollars")
                    }
                }
                if car?.estimatedValue != nil {
                    Section {
                        Button("Remove Value", role: .destructive) {
                            if let car {
                                carStore.updateValue(nil, source: .owner, showPublicly: car.showValuePublicly, for: car)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Car Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let car, let value = parsedValue else { return }
                        carStore.updateValue(value, source: .owner, showPublicly: car.showValuePublicly, for: car)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(parsedValue == nil)
                }
            }
            .onAppear {
                if let value = car?.estimatedValue {
                    valueText = CarValueInput.format(value)
                }
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Parsing/formatting for the whole-dollar value fields.
enum CarValueInput {
    /// Accepts "31000", "31,000", "$31,000". nil for empty, zero or absurd input.
    static func parse(_ text: String) -> Double? {
        let digits = text.filter(\.isNumber)
        guard let value = Double(digits), value > 0, value < 100_000_000 else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.automatic))
    }
}
