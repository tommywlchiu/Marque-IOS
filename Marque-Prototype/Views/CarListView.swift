import SwiftUI

struct CarListView: View {
    @EnvironmentObject var carStore: CarStore
    @State private var showingAddCar = false

    var body: some View {
        NavigationStack {
            Group {
                if carStore.cars.isEmpty {
                    emptyStateView
                } else {
                    carList
                }
            }
            .navigationTitle("My Cars")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddCar = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCar) {
                AddCarView()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Cars Added Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the button below to add your first car and store its information.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showingAddCar = true
            } label: {
                Label("Add a Car", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }

    private var carList: some View {
        List {
            ForEach(carStore.cars) { car in
                NavigationLink(destination: CarDetailView(car: car)) {
                    CarRowView(car: car)
                }
            }
            .onDelete(perform: carStore.deleteCar)

            Section {
                Button {
                    showingAddCar = true
                } label: {
                    Label("Add a Car", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
    }
}

struct CarRowView: View {
    let car: Car

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "car.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(car.displayName)
                    .font(.headline)

                if !car.licensePlate.isEmpty {
                    Text("Plate: \(car.licensePlate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Tap to add details")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CarListView()
        .environmentObject(CarStore())
}
