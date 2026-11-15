import UIKit

/// Keeps photos of imported cookbook pages/recipe cards so the recipe shows the original.
/// Recipes store a "local:<file>" reference rather than a path, because the app's
/// container path can change between installs and updates.
enum RecipePhotoStore {
    static let prefix = "local:"
    private static let cache = NSCache<NSString, UIImage>()

    private static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecipePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            return prefix + name
        } catch {
            return nil
        }
    }

    static func image(for ref: String) -> UIImage? {
        guard ref.hasPrefix(prefix) else { return nil }
        let name = String(ref.dropFirst(prefix.count))
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: folder.appendingPathComponent(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    static func delete(_ ref: String?) {
        guard let ref, ref.hasPrefix(prefix) else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(String(ref.dropFirst(prefix.count))))
    }
}
