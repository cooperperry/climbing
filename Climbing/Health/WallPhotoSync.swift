import UIKit

/// Shrink a wall photo so WatchConnectivity can send today's map. Pins stay
/// in 0...1 space, so any thumbnail still lines up.
enum WallPhotoSync {
    static let maxPixel: CGFloat = 240

    static func thumbnail(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxPixel ? maxPixel / longest : 1
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let small = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.42)
    }
}
