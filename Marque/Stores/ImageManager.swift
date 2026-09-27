import UIKit

// Static funcs only, no shared mutable state — safe to call from any thread,
// including off-main decode work the frontend may do.
struct ImageManager {
    // Shared by every car-photo save/upload path (CarStore's receipt path
    // uses its own quality but shares this same resize via `downscaled`).
    static let maxDimension: CGFloat = 2000
    private static let jpegQuality: CGFloat = 0.8

    private static var photosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CarPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// On-disk location for a given car-photo/receipt file name, so callers
    /// (e.g. ImageIO-based downsampling done off ImageManager's own decode
    /// path) can read straight from disk without going through `loadImage`.
    static func fileURL(for fileName: String) -> URL {
        photosDirectory.appendingPathComponent(fileName)
    }

    /// Resizes `image` so its longest side is at most `maxDimension` **pixels**.
    /// A no-op (returns `image` unchanged) if it's already within bounds.
    ///
    /// Measured and rendered in pixels on purpose: `UIImage.size` is in points,
    /// and `UIGraphicsImageRenderer` renders at the screen scale (3x) unless told
    /// otherwise, so a points-based "2000" produced 6000px files.
    static func downscaled(_ image: UIImage, maxDimension: CGFloat = maxDimension) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let maxSide = max(pixelSize.width, pixelSize.height)
        guard maxSide > maxDimension, maxSide > 0 else { return image }
        let ratio = maxDimension / maxSide
        let newSize = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    // Full camera-resolution photos (~4032x3024) were the main source of the
    // owner-reported slowness — both the on-disk cache and the Storage
    // upload. Downscale before encoding so every saved/uploaded copy is
    // capped at maxDimension.
    static func saveImage(_ image: UIImage, fileName: String) {
        guard let data = downscaled(image).jpegData(compressionQuality: jpegQuality) else { return }
        try? data.write(to: fileURL(for: fileName), options: .atomic)
    }

    static func loadImage(fileName: String) -> UIImage? {
        let url = fileURL(for: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        // One-time migration: a photo saved before the downscale-on-save
        // change above (or synced down from an older client) may still be at
        // full camera resolution. Re-save it downscaled here so every later
        // load is cheap. Returns the downscaled image immediately rather than
        // the original decode, since we already have it in memory.
        guard max(image.size.width, image.size.height) * image.scale > maxDimension else { return image }
        let resized = downscaled(image)
        if let data = resized.jpegData(compressionQuality: jpegQuality) {
            try? data.write(to: url, options: .atomic)
        }
        return resized
    }

    static func deleteImage(fileName: String) {
        try? FileManager.default.removeItem(at: fileURL(for: fileName))
    }

    static func generateFileName() -> String {
        "\(UUID().uuidString).jpg"
    }
}
