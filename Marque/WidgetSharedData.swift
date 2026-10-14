import Foundation

/// Snapshot of one car for the Home Screen widget. Written by the app
/// (`WidgetSnapshotService`) into the shared App Group container whenever
/// `CarStore.cars` changes; read by the widget extension's timeline
/// provider. The widget process never touches Firestore, CarStore, or
/// anything else app-side directly — this file (and `GarageTheme.swift`,
/// shared the same way) is the entire surface between the two.
struct WidgetCarSnapshot: Codable, Identifiable, Equatable {
    let id: String
    let displayName: String
    /// nil when the car has no mileage set.
    let mileageText: String?
    /// The same single most-urgent line `GarageSummary.statusLine` shows on
    /// the Garage home — kept in sync by construction, since both read from
    /// the same `Car`.
    let statusText: String
    let needsAttention: Bool
    /// Filename of the hero image copied into the shared container (the
    /// same PNG the Garage hero itself renders/caches) — nil until one has
    /// been produced for this car.
    let heroImageFileName: String?
}

/// Read/write access to the widget's slice of the shared App Group
/// container. Every call is a plain file read/write — fast and synchronous,
/// safe to call from the widget extension's timeline provider.
enum WidgetSharedStore {
    static let appGroupID = "group.com.tommychiu.marque"
    private static let carsFileName = "widget_cars.json"
    private static let heroImagesDirectoryName = "WidgetHeroImages"
    private static let selectedCarFileName = "widget_selected_car.txt"
    /// `CarEntity.id` of the "Current Car" choice: a widget set to it shows
    /// whichever car is selected in the Garage, and follows it when it changes.
    static let followSelectedCarID = "__selected__"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var heroImagesDirectory: URL? {
        containerURL?.appendingPathComponent(heroImagesDirectoryName, isDirectory: true)
    }

    static func heroImageURL(fileName: String) -> URL? {
        heroImagesDirectory?.appendingPathComponent(fileName)
    }

    static func writeCars(_ cars: [WidgetCarSnapshot]) {
        guard let container = containerURL, let data = try? JSONEncoder().encode(cars) else { return }
        try? data.write(to: container.appendingPathComponent(carsFileName), options: .atomic)
    }

    /// The car selected in the Garage (the app's `garage.selectedCarID`), so a
    /// widget set to "Current Car" can follow it.
    static func writeSelectedCarID(_ id: String?) {
        guard let container = containerURL else { return }
        let url = container.appendingPathComponent(selectedCarFileName)
        guard let id, !id.isEmpty else { try? FileManager.default.removeItem(at: url); return }
        try? Data(id.utf8).write(to: url, options: .atomic)
    }

    static func readSelectedCarID() -> String? {
        guard let container = containerURL,
              let data = try? Data(contentsOf: container.appendingPathComponent(selectedCarFileName)),
              let id = String(data: data, encoding: .utf8), !id.isEmpty else { return nil }
        return id
    }

    static func readCars() -> [WidgetCarSnapshot] {
        guard let container = containerURL,
              let data = try? Data(contentsOf: container.appendingPathComponent(carsFileName)),
              let cars = try? JSONDecoder().decode([WidgetCarSnapshot].self, from: data) else { return [] }
        return cars
    }
}
