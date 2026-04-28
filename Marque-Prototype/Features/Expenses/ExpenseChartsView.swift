import SwiftUI
import Charts

struct ExpenseChartsView: View {
    @EnvironmentObject var carStore: CarStore
    @State private var selectedPeriod: ExpensePeriod = .year

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                periodPicker

                totalCard

                if categoryTotals.isEmpty {
                    MarqueEmptyState(
                        icon: "chart.bar.xaxis",
                        title: "No Spend in This Period",
                        subtitle: "Add maintenance records with a cost to see breakdowns here."
                    )
                    .padding(.top, 40)
                } else {
                    categoryChartCard
                    monthlyChartCard
                    perVehicleCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Expense Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod.animation()) {
            ForEach(ExpensePeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var totalCard: some View {
        VStack(spacing: 4) {
            Text("Total Spent").font(.caption).foregroundColor(.secondary)
            Text(formatCurrency(totalSpend))
                .font(.system(size: 36, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var categoryChartCard: some View {
        chartCard(title: "By Category") {
            Chart(categoryTotals, id: \.category) { item in
                BarMark(
                    x: .value("Amount", item.amount),
                    y: .value("Category", item.category)
                )
                .foregroundStyle(.linearGradient(
                    colors: [.accentColor, .accentColor.opacity(0.6)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .annotation(position: .trailing) {
                    Text(formatCurrency(item.amount))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(max(categoryTotals.count, 1)) * 36 + 20)
        }
    }

    private var monthlyChartCard: some View {
        chartCard(title: "Monthly Trend") {
            Chart(monthlyTotals, id: \.month) { point in
                LineMark(
                    x: .value("Month", point.month),
                    y: .value("Spend", point.amount)
                )
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Month", point.month),
                    y: .value("Spend", point.amount)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.linearGradient(
                    colors: [.accentColor.opacity(0.4), .accentColor.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                PointMark(
                    x: .value("Month", point.month),
                    y: .value("Spend", point.amount)
                )
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 200)
        }
    }

    private var perVehicleCard: some View {
        chartCard(title: "By Vehicle") {
            VStack(spacing: 10) {
                ForEach(perVehicleTotals, id: \.car.id) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.car.displayName)
                                .font(.subheadline).fontWeight(.medium)
                            Spacer()
                            Text(formatCurrency(entry.amount))
                                .font(.subheadline).fontWeight(.semibold)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * proportion(of: entry.amount))
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Derived data

    private var totalSpend: Double {
        carStore.cars.reduce(0) { $0 + $1.expenses(in: selectedPeriod) }
    }

    private var categoryTotals: [(category: String, amount: Double)] {
        var grouped: [String: Double] = [:]
        for car in carStore.cars {
            for item in car.expensesByCategory(in: selectedPeriod) {
                grouped[item.category, default: 0] += item.amount
            }
        }
        return grouped
            .map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    private var perVehicleTotals: [(car: Car, amount: Double)] {
        carStore.cars
            .map { (car: $0, amount: $0.expenses(in: selectedPeriod)) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    // Bucket maintenance records into months for the line chart.
    private var monthlyTotals: [(month: Date, amount: Double)] {
        let cal = Calendar.current
        let cutoff = cutoffDate(for: selectedPeriod)
        var bucket: [Date: Double] = [:]

        for car in carStore.cars {
            for record in car.maintenanceRecords {
                guard record.date >= cutoff,
                      let cost = Double(record.cost), cost > 0,
                      let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: record.date))
                else { continue }
                bucket[monthStart, default: 0] += cost
            }
        }

        return bucket
            .map { (month: $0.key, amount: $0.value) }
            .sorted { $0.month < $1.month }
    }

    private func proportion(of value: Double) -> CGFloat {
        let max = perVehicleTotals.first?.amount ?? 1
        return max > 0 ? CGFloat(value / max) : 0
    }

    private func cutoffDate(for period: ExpensePeriod) -> Date {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .month:     return cal.date(byAdding: .month, value: -1, to: now) ?? now
        case .sixMonths: return cal.date(byAdding: .month, value: -6, to: now) ?? now
        case .year:      return cal.date(byAdding: .year, value: -1, to: now) ?? now
        case .allTime:   return .distantPast
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value < 100 ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}

#Preview {
    NavigationStack {
        ExpenseChartsView()
    }
    .environmentObject({
        let store = CarStore()
        store.cars = CarStore.previewCars
        return store
    }())
}
