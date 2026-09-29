import SwiftUI

/// "Estimate with AI": pick a condition (and optionally a region), get a
/// range with the model's rationale and confidence, then save the suggested
/// value as-is (source `.ai`) or edit it first (source `.owner`).
/// `CarStore.estimateValue` saves nothing; only "Save Value" does.
struct EstimateValueSheet: View {
    let carID: UUID

    @EnvironmentObject private var carStore: CarStore
    @Environment(\.dismiss) private var dismiss

    @State private var condition: ValueCondition = .good
    @State private var region = ""
    @State private var isEstimating = false
    @State private var estimate: ValueEstimate?
    @State private var errorMessage: String?
    @State private var limitReached = false
    @State private var valueText = ""

    private var car: Car? { carStore.cars.first(where: { $0.id == carID }) }
    private var parsedValue: Double? { CarValueInput.parse(valueText) }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Condition")) {
                    Picker("Condition", selection: $condition) {
                        ForEach(ValueCondition.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("ZIP code or area (optional)", text: $region)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section {
                    MarquePrimaryButton(estimate == nil ? "Get Estimate" : "Estimate Again", isLoading: isEstimating) {
                        Task { await runEstimate() }
                    }
                    .disabled(limitReached)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if let car {
                        Text("Based on \(car.displayName)\(car.mileage.isEmpty ? "" : ", \(car.mileage) mi") and the condition you pick.")
                    }
                }

                if let errorMessage {
                    Section {
                        MarqueErrorBanner(message: errorMessage)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                if let estimate {
                    resultSection(estimate)
                    saveSection(estimate)
                }
            }
            .navigationTitle("Estimate Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Result

    private func resultSection(_ estimate: ValueEstimate) -> some View {
        Section(
            header: Text("Estimated Range"),
            footer: Text(remainingText(estimate))
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(currency(estimate.low)) – \(currency(estimate.high))")
                        .font(.title2.weight(.bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    confidenceBadge(estimate.confidence)
                }
                Text("Most likely around \(currency(estimate.mid))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if !estimate.rationale.isEmpty {
                    Label {
                        Text(estimate.rationale)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "sparkles").foregroundColor(.accentColor)
                    }
                    .padding(.top, 2)
                }
                Text("AI estimate, not an appraisal. Real prices vary with history, options and the local market.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func saveSection(_ estimate: ValueEstimate) -> some View {
        Section(
            header: Text("Value to Save"),
            footer: Text("Only you can see the exact figure. You choose separately whether a rounded range shows on your public car.")
        ) {
            HStack(spacing: 8) {
                pickChip("Low", estimate.low)
                pickChip("Mid", estimate.mid)
                pickChip("High", estimate.high)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            HStack {
                Text("$").foregroundColor(.secondary)
                TextField("Value", text: $valueText)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Value to save, in US dollars")
            }
            Button {
                save(estimate)
            } label: {
                Text("Save Value")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .disabled(parsedValue == nil)
        }
    }

    private func pickChip(_ title: String, _ value: Double) -> some View {
        let isSelected = parsedValue.map { Int($0) == Int(value.rounded()) } ?? false
        return Button {
            valueText = CarValueInput.format(value)
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.caption2.weight(.semibold))
                Text(currency(value)).font(.caption.weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color(.systemGray6))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(currency(value))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func confidenceBadge(_ confidence: ValueEstimate.Confidence) -> some View {
        let (label, color): (String, Color) = {
            switch confidence {
            case .high: return ("High confidence", .green)
            case .medium: return ("Medium confidence", .orange)
            case .low: return ("Low confidence", .secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .fixedSize()
    }

    private func remainingText(_ estimate: ValueEstimate) -> String {
        let left = max(0, estimate.dailyLimit - estimate.estimatesUsedToday)
        return "\(left) of \(estimate.dailyLimit) estimates left today"
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    // MARK: - Actions

    private func runEstimate() async {
        guard let car, !isEstimating else { return }
        isEstimating = true
        errorMessage = nil
        defer { isEstimating = false }
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await carStore.estimateValue(
                for: car,
                condition: condition,
                region: trimmedRegion.isEmpty ? nil : trimmedRegion
            )
            withAnimation { estimate = result }
            valueText = CarValueInput.format(result.mid)
            limitReached = result.estimatesUsedToday >= result.dailyLimit
        } catch let error as CarValueService.ValueError {
            if error == .dailyLimit { limitReached = true }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ estimate: ValueEstimate) {
        guard let car, let value = parsedValue else { return }
        // Picking one of the AI figures unchanged counts as the AI's value;
        // anything the owner typed is theirs.
        let aiFigures = [estimate.low, estimate.mid, estimate.high].map { Int($0.rounded()) }
        let source: CarValueSource = aiFigures.contains(Int(value)) ? .ai : .owner
        carStore.updateValue(value, source: source, showPublicly: car.showValuePublicly, for: car)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
