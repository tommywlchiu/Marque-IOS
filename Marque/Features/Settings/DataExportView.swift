import SwiftUI

/// FR-15: service & expense report export (PDF + CSV) — free for every user,
/// not a Pro benefit (FR-15.1). Reached from SettingsView's "Data" section.
/// Delivery is the iOS share sheet only (FR-15.6): the app never emails,
/// uploads, or otherwise transmits the export itself.
struct DataExportView: View {
    @EnvironmentObject var carStore: CarStore

    private enum Scope: Hashable {
        case allCars
        case single(UUID)
    }

    private enum ExportFormat {
        case pdf
        case csv
    }

    @State private var scope: Scope = .allCars
    @State private var period: ExpenseReportPeriod = .rolling(.year)
    @State private var didSetInitialDefault = false
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var shareItem: ShareItem?

    var body: some View {
        Group {
            if carStore.cars.isEmpty {
                MarqueEmptyState(
                    icon: "square.and.arrow.up",
                    title: "Nothing to Export Yet",
                    subtitle: "Add a car and log some service or expenses, then come back here to export a PDF or CSV report."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    scopeSection
                    periodSection
                    summarySection
                    if let generationError {
                        Section {
                            MarqueErrorBanner(message: generationError)
                        }
                        .listRowBackground(Color.clear)
                    }
                    exportSection
                }
            }
        }
        .navigationTitle("Export Service & Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didSetInitialDefault else { return }
            didSetInitialDefault = true
            period = ExpenseReportPeriod.defaultSelection(cars: carStore.cars)
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
    }

    // MARK: - Sections

    private var scopeSection: some View {
        Section(header: Text("Scope")) {
            Picker("Scope", selection: $scope) {
                Text("All Cars (Garage)").tag(Scope.allCars)
                ForEach(carStore.cars) { car in
                    Text(car.displayName).tag(Scope.single(car.id))
                }
            }
            .accessibilityLabel("Export scope")
        }
    }

    private var periodSection: some View {
        Section(header: Text("Period")) {
            Picker("Period", selection: $period) {
                ForEach(ExpenseReportPeriod.allOptions(cars: carStore.cars)) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .accessibilityLabel("Export period")
        }
    }

    private var summarySection: some View {
        Section {
            HStack {
                Text("\(recordCount) record\(recordCount == 1 ? "" : "s")")
                Spacer()
                Text(formattedTotal)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    private var exportSection: some View {
        Section {
            if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Generating…")
                        .foregroundColor(.secondary)
                }
            } else {
                // Not disabled when `scopedRecords` is empty: a zero-record
                // report is still a legitimate export for this period (e.g.
                // documenting "no deductible expenses this year") — both
                // generators already handle that case explicitly rather
                // than producing a blank/broken file.
                Button {
                    export(format: .pdf)
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }

                Button {
                    export(format: .csv)
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            }

        } footer: {
            Text("Exports are shared directly from your device. Marque never emails or uploads them on your behalf.")
        }
    }

    // MARK: - Derived data

    private var scopedCars: [Car] {
        switch scope {
        case .allCars:
            return carStore.cars
        case .single(let id):
            return carStore.cars.filter { $0.id == id }
        }
    }

    private var scopedRecords: [MaintenanceRecord] {
        scopedCars.flatMap { car in
            car.maintenanceRecords.filter { period.contains($0.date) }
        }
    }

    private var recordCount: Int { scopedRecords.count }

    private var totalAmount: Double {
        scopedRecords.compactMap { $0.costValue }.reduce(0, +)
    }

    private var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: totalAmount)) ?? "$0.00"
    }

    // MARK: - Export

    /// Snapshots `carStore.cars` on the main actor (it's `@MainActor`-owned),
    /// then hops to a background task for the actual PDF/CSV rendering —
    /// the heavy part for a large garage — before writing the temp file and
    /// presenting the share sheet.
    private func export(format: ExportFormat) {
        generationError = nil
        isGenerating = true

        let cars = scopedCars
        let period = self.period
        let filename = exportFilename(format: format)

        Task {
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                switch format {
                case .pdf:
                    return ExpenseReportPDF.generate(cars: cars, period: period)
                case .csv:
                    return ExpenseReportCSV.generate(cars: cars, period: period).data(using: .utf8)
                }
            }.value

            await MainActor.run {
                isGenerating = false
                guard let data else {
                    generationError = "Couldn't generate the export. Please try again."
                    return
                }
                do {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    try data.write(to: url, options: .atomic)
                    shareItem = ShareItem(url: url)
                } catch {
                    generationError = "Couldn't save the export file."
                }
            }
        }
    }

    private func exportFilename(format: ExportFormat) -> String {
        var parts = ["Marque-expenses", filenameSlug(period.displayName)]
        if case .single(let id) = scope, let car = carStore.cars.first(where: { $0.id == id }) {
            parts.append(filenameSlug(car.displayName))
        }
        let ext = format == .pdf ? "pdf" : "csv"
        return parts.joined(separator: "-") + "." + ext
    }

    /// Lowercase, hyphen-separated, filesystem-safe slug — collapses any run
    /// of non `[a-z0-9]` characters (spaces, punctuation) into one hyphen.
    private func filenameSlug(_ raw: String) -> String {
        var result = ""
        var lastWasHyphen = false
        for scalar in raw.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                result.unicodeScalars.append(scalar)
                lastWasHyphen = false
            } else if !lastWasHyphen && !result.isEmpty {
                result.append("-")
                lastWasHyphen = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "export" : result
    }
}

// MARK: - Share sheet

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Thin wrapper for presenting the standard iOS share sheet (FR-15.6 requires
/// it — no in-app email/upload path). `ShareLink` can't be used directly here
/// since the file is generated on demand rather than existing ahead of time.
/// Shared with `AccountDataExportView`.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
