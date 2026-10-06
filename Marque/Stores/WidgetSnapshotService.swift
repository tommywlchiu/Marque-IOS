import Foundation
import UIKit
import WidgetKit

/// Keeps the widget's shared snapshot (`WidgetSharedStore`) in sync with
/// `CarStore.cars`. Called from `Marque.swift` whenever the car list
/// changes, the same way `NotificationManager.scheduleAll` already is.
///
/// Hero images are opportunistic, not a second rendering pipeline: a car
/// whose hero hasn't been rendered anywhere in the app yet (Vision cut-out,
/// studio render, or the SceneKit body-style model) gets no image — or only
/// the cached body-style model — in this pass, but `sync`
/// kicks off that exact same render in the background — `CarCutoutRenderer`
/// / `CarModelRenderer`, the pair `GarageHeroView` itself calls — and
/// re-syncs once it lands, so the widget picks up the real image without
/// waiting for an unrelated car-list change. A car never opened in the
/// Garage briefly shows no image, same as the Garage home would on first load.
@MainActor
enum WidgetSnapshotService {
    /// `retryRenders` is false only for the re-sync after a background
    /// render, so a car that still has no better image can't loop.
    static func sync(cars: [Car], retryRenders: Bool = true) {
        var snapshots: [WidgetCarSnapshot] = []
        var pendingRenders: [Car] = []

        for car in cars {
            let (heroFileName, isFinal) = copyCachedHeroImageIfAvailable(for: car)
            // A cached body-style model isn't final: the studio render may
            // just not be downloaded yet (it is only fetched for the car on
            // screen in the Garage), and a stale model would otherwise stick.
            if !isFinal && retryRenders { pendingRenders.append(car) }
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
            sync(cars: cars, retryRenders: false)
        }
    }

    // MARK: - Hero image

    /// Whichever of the two the Garage hero would already show is cached —
    /// the cut-out if the cover photo qualified, else the studio render, else
    /// the body-style model —
    /// copied into the shared container under the car's id. nil if none is
    /// cached yet. `isFinal` is false unless it's the cut-out or the render.
    private static func copyCachedHeroImageIfAvailable(for car: Car) -> (fileName: String?, isFinal: Bool) {
        if let fileName = car.primaryPhotoFileName,
           let cutout = CarCutoutRenderer.cachedCutout(fileName: fileName) {
            return (copyToSharedContainer(cutout, carID: car.id), true)
        }
        if let still = CarRenderLibrary.cachedStill(for: car) {
            return (copyToSharedContainer(still, carID: car.id), true)
        }
        if let model = CarModelRenderer.cachedImage(for: car) {
            return (copyToSharedContainer(model, carID: car.id), false)
        }
        return (nil, false)
    }

    /// Renders a hero image exactly the way `GarageHeroView` would.
    private static func renderAndCopyHeroImage(for car: Car) async -> String? {
        if let fileName = car.primaryPhotoFileName,
           let cutout = await CarCutoutRenderer.cutout(fileName: fileName, storageURL: car.primaryPhotoStorageURL) {
            return copyToSharedContainer(cutout, carID: car.id)
        }
        if let still = await CarRenderLibrary.still(for: car) {
            return copyToSharedContainer(still, carID: car.id)
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
