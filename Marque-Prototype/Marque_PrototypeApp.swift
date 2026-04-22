import SwiftUI

@main
struct Marque_PrototypeApp: App {
    @StateObject private var carStore = CarStore()

    var body: some Scene {
        WindowGroup {
            CarListView()
                .environmentObject(carStore)
                .onAppear {
                    NotificationManager.requestPermission()
                    NotificationManager.scheduleExpiryNotifications(for: carStore.cars)
                }
                .onChange(of: carStore.cars) { _, newCars in
                    NotificationManager.scheduleExpiryNotifications(for: newCars)
                }
        }
    }
}
