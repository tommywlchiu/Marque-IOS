import SwiftUI

@main
struct Marque_PrototypeApp: App {
    @StateObject private var carStore = CarStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                CarListView()
                    .tabItem {
                        Label("My Garage", systemImage: "car.fill")
                    }

                ExpenseSummaryView()
                    .tabItem {
                        Label("Expenses", systemImage: "dollarsign.circle.fill")
                    }
            }
            .environmentObject(carStore)
            .onAppear {
                NotificationManager.scheduleExpiryNotifications(for: carStore.cars)
            }
            .onChange(of: carStore.cars) { _, newCars in
                NotificationManager.scheduleExpiryNotifications(for: newCars)
            }
        }
    }
}
