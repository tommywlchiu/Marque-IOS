import SwiftUI

@main
struct Marque_PrototypeApp: App {
    @StateObject private var carStore = CarStore()

    var body: some Scene {
        WindowGroup {
            CarListView()
                .environmentObject(carStore)
        }
    }
}
