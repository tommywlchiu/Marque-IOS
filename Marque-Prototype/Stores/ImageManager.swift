import UIKit

struct ImageManager {
    private static var photosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CarPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func saveImage(_ image: UIImage, fileName: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let url = photosDirectory.appendingPathComponent(fileName)
        try? data.write(to: url)
    }

    static func loadImage(fileName: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func deleteImage(fileName: String) {
        let url = photosDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    static func generateFileName() -> String {
        "\(UUID().uuidString).jpg"
    }
}
