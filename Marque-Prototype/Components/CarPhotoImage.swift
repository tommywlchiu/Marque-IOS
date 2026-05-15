import SwiftUI

// Displays a car photo: loads from local disk first (instant, offline-capable),
// falls back to the Firebase Storage download URL if the file isn't cached locally.
struct CarPhotoImage: View {
    let fileName: String
    let storageURL: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let local = ImageManager.loadImage(fileName: fileName) {
            Image(uiImage: local)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let url = storageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color(.systemGray5)
    }
}
