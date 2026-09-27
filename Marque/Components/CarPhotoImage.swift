import SwiftUI

// Displays a car photo: loads from local disk first (instant, offline-capable),
// falls back to the Firebase Storage download URL if the file isn't cached locally.
//
// Decoding is off the main actor and downsampled to the view's actual displayed
// pixel size via ImageIO (`LocalPhotoLoader` / `MarqueImageCache` in
// MarqueComponents.swift) -- a 56pt list thumbnail never fully decodes a
// full-resolution camera photo just to shrink it back down, and a cache hit
// (e.g. scrolling a row back into view) paints on the first frame instead of
// flashing a placeholder.
//
// External API is unchanged from before this pass -- fileName/storageURL/contentMode
// are the same three properties every existing call site already uses.
struct CarPhotoImage: View {
    let fileName: String
    let storageURL: URL?
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: taskKey(for: geo.size)) {
                let fillAspect = contentMode == .fill && geo.size.height > 0
                    ? geo.size.width / geo.size.height : nil
                await load(pixelSize: max(geo.size.width, geo.size.height) * displayScale, fillAspect: fillAspect)
            }
        }
    }

    private func taskKey(for size: CGSize) -> String {
        "\(fileName)|\(Int(size.width))x\(Int(size.height))"
    }

    private func load(pixelSize: CGFloat, fillAspect: CGFloat?) async {
        guard pixelSize > 0 else { return }

        // Synchronous cache probe first: if this exact fileName+size was already
        // decoded, paint immediately rather than letting the placeholder show even
        // for one frame while the (otherwise-instant) async path spins up.
        if let cached = LocalPhotoLoader.cachedImage(fileName: fileName, pixelSize: pixelSize, fillAspect: fillAspect) {
            image = cached
            return
        }
        if let local = await LocalPhotoLoader.load(fileName: fileName, pixelSize: pixelSize, fillAspect: fillAspect) {
            image = local
            return
        }

        guard let storageURL else { return }
        if let cached = MarqueImageCache.shared.get(storageURL) {
            image = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: storageURL),
              let downloaded = UIImage(data: data) else { return }
        MarqueImageCache.shared.set(downloaded, for: storageURL)
        image = downloaded

        // Backfill local disk so the next load for this car is instant and
        // offline-capable, matching the "local first" contract this view documents.
        // Off-main since ImageManager.saveImage does synchronous file I/O + JPEG encode.
        Task.detached(priority: .utility) {
            ImageManager.saveImage(downloaded, fileName: fileName)
        }
    }

    private var placeholder: some View {
        Color(.systemGray5)
    }
}
