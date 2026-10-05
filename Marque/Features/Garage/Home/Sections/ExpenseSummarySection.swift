import SwiftUI

/// All-time spend for one car, by category. Extracted from CarDetailView;
/// used there and on the Garage's Expenses screen.
struct ExpenseSummarySection: View {
    let car: Car

    var body: some View {
        Section(header: Text("Expense Summary")) {
            HStack {
                Text("Total Spent").foregroundColor(.secondary)
                Spacer()
                Text(car.totalExpenses, format: .currency(code: "USD")).fontWeight(.semibold)
            }
            ForEach(car.expensesByCategory(in: .allTime), id: \.category) { item in
                HStack {
                    Text(item.category).font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text(item.amount, format: .currency(code: "USD")).font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
        .garageRowBackground()
    }
}
