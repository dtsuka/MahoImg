import CoreGraphics
import Foundation

enum CropDragAction: Equatable {
    case move
    case resize(ResizeAnchor)
}

enum ResizeAnchor: Equatable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    func resized(rect: CropRect, dx: Double, dy: Double) -> CropRect {
        switch self {
        case .topLeft:
            return CropRect(x: rect.x, y: rect.y, width: rect.width + dx, height: rect.height + dy)
        case .topRight:
            return CropRect(x: rect.x + dx, y: rect.y, width: rect.width - dx, height: rect.height + dy)
        case .bottomLeft:
            return CropRect(x: rect.x, y: rect.y + dy, width: rect.width + dx, height: rect.height - dy)
        case .bottomRight:
            return CropRect(x: rect.x + dx, y: rect.y + dy, width: rect.width - dx, height: rect.height - dy)
        }
    }
}

enum CropInteraction {
    static let defaultHitSize = 24.0

    static func dragAction(
        at point: CGPoint,
        cropRect: CropRect,
        mapper: PreviewMapper,
        hitSize: Double = defaultHitSize
    ) -> CropDragAction? {
        let cropFrame = mapper.viewRect(from: cropRect)

        if point.distance(to: CGPoint(x: cropFrame.minX, y: cropFrame.minY)) <= hitSize {
            return .resize(.bottomRight)
        }
        if point.distance(to: CGPoint(x: cropFrame.maxX, y: cropFrame.minY)) <= hitSize {
            return .resize(.bottomLeft)
        }
        if point.distance(to: CGPoint(x: cropFrame.minX, y: cropFrame.maxY)) <= hitSize {
            return .resize(.topRight)
        }
        if point.distance(to: CGPoint(x: cropFrame.maxX, y: cropFrame.maxY)) <= hitSize {
            return .resize(.topLeft)
        }
        return cropFrame.contains(point) ? .move : nil
    }

    static func updatedCropRect(
        action: CropDragAction,
        startRect: CropRect,
        dx: Double,
        dy: Double,
        imageSize: CGSize
    ) -> CropRect {
        switch action {
        case .move:
            return CropRect(
                x: startRect.x + dx,
                y: startRect.y + dy,
                width: startRect.width,
                height: startRect.height
            ).clamped(to: imageSize)
        case .resize(let anchor):
            return anchor.resized(rect: startRect, dx: dx, dy: dy).clamped(to: imageSize)
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
