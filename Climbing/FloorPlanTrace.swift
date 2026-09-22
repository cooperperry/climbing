import UIKit
import Vision

/// Turns a photo or sketch of a floor plan into wall polylines aligned with the underlay.
enum FloorPlanTrace {
    static func wallPolylines(from image: UIImage, fittedIn viewSize: CGSize) -> [[PlanPoint]] {
        guard let cgImage = image.cgImage, viewSize.width > 1, viewSize.height > 1 else { return [] }
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 2
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 768
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNContoursObservation else { return [] }

        var contours: [[CGPoint]] = []
        collect(observation.topLevelContours, into: &contours)
        let frame = fittedImageRect(image: image.size, view: viewSize)

        var walls: [(points: [PlanPoint], length: Double)] = []
        for contour in contours {
            let board = contour.map { imagePoint($0, frame: frame, view: viewSize) }
            guard spansMostOfTheImage(contour) == false else { continue }
            let simplified = FloorPlanMath.simplify(board, tolerance: 0.012)
            guard simplified.count >= 2 else { continue }
            let length = polylineLength(simplified)
            guard length > 0.08 else { continue }
            let closed = FloorPlanMath.distance(simplified[0], simplified[simplified.count - 1]) < 0.03
            let points = closed && simplified.count > 3 ? Array(simplified.dropLast()) : simplified
            walls.append((points, length))
        }
        return walls
            .sorted { $0.length > $1.length }
            .prefix(16)
            .map(\.points)
    }

    private static func collect(_ contours: [VNContour], into output: inout [[CGPoint]]) {
        for contour in contours {
            let count = contour.pointCount
            if count >= 2 {
                let pointer = contour.normalizedPoints
                var points: [CGPoint] = []
                points.reserveCapacity(count)
                for index in 0 ..< count {
                    let point = pointer[index]
                    points.append(CGPoint(x: CGFloat(point.x), y: CGFloat(1 - point.y)))
                }
                output.append(points)
            }
            let children = (0 ..< contour.childContourCount).compactMap { index in
                try? contour.childContour(at: index)
            }
            if children.isEmpty == false {
                collect(children, into: &output)
            }
        }
    }

    private static func spansMostOfTheImage(_ points: [CGPoint]) -> Bool {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return false }
        return (maxX - minX) > 0.92 && (maxY - minY) > 0.92
    }

    private static func fittedImageRect(image: CGSize, view: CGSize) -> CGRect {
        let scale = min(view.width / max(image.width, 1), view.height / max(image.height, 1))
        let width = image.width * scale
        let height = image.height * scale
        return CGRect(
            x: (view.width - width) / 2,
            y: (view.height - height) / 2,
            width: width,
            height: height
        )
    }

    private static func imagePoint(_ point: CGPoint, frame: CGRect, view: CGSize) -> PlanPoint {
        PlanPoint(
            x: (frame.minX + point.x * frame.width) / max(view.width, 1),
            y: (frame.minY + point.y * frame.height) / max(view.height, 1)
        )
    }

    private static func polylineLength(_ points: [PlanPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        return (1 ..< points.count).reduce(0) { partial, index in
            partial + FloorPlanMath.distance(points[index - 1], points[index])
        }
    }
}
