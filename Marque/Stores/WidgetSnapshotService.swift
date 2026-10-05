import Foundation
import UIKit
import WidgetKit

/// Keeps the widget's shared snapshot (`WidgetSharedStore`) in sync with
/// `CarStore.cars`. Called from `Marque.swift` whenever the car list
/// changes, the same way `NotificationManager.scheduleAll` already is.
///
/// Hero images are opportunistic, not a second rendering pipeline: a car
/// whose hero hasn't been rendered anywhere in the app yet (Vision cut-out
/// or the SceneKit body-style model) gets no image in this pass, but `sync`
/// kicks off that exact same render in the background — `CarCutoutRenderer`
/// / `CarModelRenderer`, the pair `GarageHeroView` itself calls — and
/// re-syncs once it lands, so the widget picks up the real image without
/// waiting for an unrelated car-list change. A car never opened in the
/// Garage briefly shows no image, same as the Garage home would on first load.
@MainActor
enum WidgetSnapshotService {
    static func sync(cars: [Car]) {
        var snapshots: [WidgetCarSnapshot] = []
        var pendingRenders: [Car] = []

        for car in cars {
            let heroFileName = copyCachedHeroImageIfAvailable(for: car)
            if heroFileName == nil { pendingRenders.append(car) }
            let status = GarageSummary.statusLine(for: car)
            snapshots.append(WidgetCarSnapshot(
                id: car.id.uuidString,
                displayName: car.displayName,
                mileageText: GarageSummary.mileageText(car),
                statusText: status.text,
                needsAttention: status.needsAttention,
                heroImageFileName: heroFileName
            ))
        }

        WidgetSharedStore.writeCars(snapshots)
        WidgetCenter.shared.reloadAllTimelines()

        guard !pendingRenders.isEmpty else { return }
        Task {
            for car in pendingRenders {
                _ = await renderAndCopyHeroImage(for: car)
            }
            sync(cars: cars)
        }
    }

    // MARK: - Hero image

    /// Whichever of the two the Garage hero would already show is cached —
    /// the cut-out if the cover photo qualified, else the body-style model —
    /// copied into the shared container under the car's id. nil if neither
    /// is cached yet.
    private static func copyCachedHeroImageIfAvailable(for car: Car) -> String? {
        if let fileName = car.primaryPhotoFileName,
           let cutout = CarCutoutRenderer.cachedCutout(fileName: fileName) {
            return copyToSharedContainer(cutout, carID: car.id)
        }
        if let model = CarModelRenderer.cachedImage(for: car) {
            return copyToSharedContainer(model, carID: car.id)
        }
        return nil
    }

    /// Renders a hero image exactly the way `GarageHeroView` would.
    private static func renderAndCopyHeroImage(for car: Car) async -> String? {
        if let fileName = car.primaryPhotoFileName,
           let cutout = await CarCutoutRenderer.cutout(fileName: fileName, storageURL: car.primaryPhotoStorageURL) {
            return copyToSharedContainer(cutout, carID: car.id)
        }
        if let model = await CarModelRenderer.image(for: car) {
            return copyToSharedContainer(model, carID: car.id)
        }
        return nil
    }

    private static func copyToSharedContainer(_ image: UIImage, carID: UUID) -> String? {
        guard let directory = WidgetSharedStore.heroImagesDirectory else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = image.pngData() else { return nil }
        let fileName = "\(carID.uuidString).png"
        do {
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }
}
