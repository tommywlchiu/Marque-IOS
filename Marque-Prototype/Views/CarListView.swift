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
            .navigationTitle("My Garage")
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
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemGray6))
                    .frame(width: 120, height: 120)

                Image(systemName: "garage.open")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("Your Garage is Empty")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Add your first car to start tracking\nyour vehicle information.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingAddCar = true
            } label: {
                Label("Add a Car", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }

    private var carList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(carStore.cars) { car in
                    NavigationLink(destination: CarDetailView(car: car)) {
                        CarCardView(car: car)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showingAddCar = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("Add a Car")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    )
                }
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}

struct CarCardView: View {
    let car: Car

    private var carColorDot: Color {
        switch car.color.lowercased() {
        case "black": return .black
        case "white": return .white
        case "silver", "gray", "grey": return .gray
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "brown": return .brown
        case "purple": return .purple
        default: return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            carThumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(car.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    if !car.color.isEmpty {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(carColorDot)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                                )
                            Text(car.color)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !car.licensePlate.isEmpty {
                        Text(car.licensePlate)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                if car.hasExpiryWarning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                        Text(car.isInsuranceExpired || car.isRegistrationExpired ? "Action needed" : "Expiring soon")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(car.isInsuranceExpired || car.isRegistrationExpired ? .red : .orange)
                } else if !car.maintenanceRecords.isEmpty {
                    Text("\(car.maintenanceRecords.count) service record\(car.maintenanceRecords.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.accentColor.opacity(0.8))
                } else if car.color.isEmpty && car.licensePlate.isEmpty {
                    Text("Tap to add details")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var carThumbnail: some View {
        if let fileName = car.photoFileName,
           let uiImage = ImageManager.loadImage(fileName: fileName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
    }
}

#Preview {
    CarListView()
        .environmentObject(CarStore())
}
