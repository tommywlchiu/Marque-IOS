import SwiftUI

struct ExpenseSummaryView: View {
    @EnvironmentObject var carStore: CarStore
    @State private var selectedPeriod: ExpensePeriod = .year

    private var totalAcrossAllCars: Double {
        carStore.cars.reduce(0) { $0 + $1.expenses(in: selectedPeriod) }
    }

    private var carsWithExpenses: [Car] {
        carStore.cars.filter { $0.expenses(in: selectedPeriod) > 0 }
    }

    private var allCategoryTotals: [(category: String, amount: Double)] {
        var grouped: [String: Double] = [:]
        for car in carStore.cars {
            for item in car.expensesByCategory(in: selectedPeriod) {
                grouped[item.category, default: 0] += item.amount
            }
        }
        return grouped.map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(ExpensePeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section {
                    VStack(spacing: 4) {
                        Text("Total Spent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(formatCurrency(totalAcrossAllCars))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(totalAcrossAllCars > 0 ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                if totalAcrossAllCars > 0 {
                    Section {
                        NavigationLink(destination: ExpenseChartsView()) {
                            Label("View Charts & Insights", systemImage: "chart.xyaxis.line")
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                if !carsWithExpenses.isEmpty {
                    Section(header: Text("By Vehicle")) {
                        ForEach(carsWithExpenses) { car in
                            HStack {
                                carIcon(for: car)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(car.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("\(car.maintenanceRecords.count) record\(car.maintenanceRecords.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(formatCurrency(car.expenses(in: selectedPeriod)))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                    }

                    Section(header: Text("By Category")) {
                        ForEach(allCategoryTotals, id: \.category) { item in
                            HStack {
                                Text(item.category)
                                    .font(.subheadline)
                                Spacer()
                                Text(formatCurrency(item.amount))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "dollarsign.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.4))

                            Text("No Expenses Yet")
                                .font(.headline)

                            Text("Expenses from service records will appear here.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Expenses")
        }
    }

    @ViewBuilder
    private func carIcon(for car: Car) -> some View {
        // CarPhotoImage decodes off-main and downsamples to this 36pt frame via
        // ImageIO, instead of the previous synchronous full-resolution main-thread decode.
        if let fileName = car.primaryPhotoFileName {
            CarPhotoImage(fileName: fileName, storageURL: car.primaryPhotoStorageURL)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "car.fill")
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}
