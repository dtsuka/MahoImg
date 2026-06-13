import CoreGraphics
import Foundation

struct PreviewMapper: Equatable {
    let imageSize: CGSize
    let viewportSize: CGSize
    var zoomScale: CGFloat = 1
    var panOffset: CGSize = .zero
    var contentInset: CGFloat = 0

    var fitScale: CGFloat {
        let availableSize = insetViewportSize
        guard imageSize.width > 0, imageSize.height > 0, availableSize.width > 0, availableSize.height > 0 else {
            return 0
        }
        return min(availableSize.width / imageSize.width, availableSize.height / imageSize.height)
    }

    var displayScale: CGFloat {
        fitScale * max(zoomScale, 0)
    }

    func zoomScale(forActualPixelScale targetScale: CGFloat, screenScale: CGFloat) -> CGFloat {
        let actualFitScale = fitScale * screenScale
        guard actualFitScale > 0 else { return 1 }
        return targetScale / actualFitScale
    }

    var imageFrame: CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return .zero
        }
        let scale = displayScale
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let offset = clampedPanOffset
        return CGRect(
            x: (viewportSize.width - width) / 2 + offset.width,
            y: (viewportSize.height - height) / 2 + offset.height,
            width: width,
            height: height
        )
    }

    var clampedPanOffset: CGSize {
        let availableSize = insetViewportSize
        let baseScale = fitScale
        guard baseScale.isFinite else { return .zero }
        let width = imageSize.width * baseScale * max(zoomScale, 0)
        let height = imageSize.height * baseScale * max(zoomScale, 0)
        let maxX = max(0, (width - availableSize.width) / 2)
        let maxY = max(0, (height - availableSize.height) / 2)
        return CGSize(
            width: min(max(panOffset.width, -maxX), maxX),
            height: min(max(panOffset.height, -maxY), maxY)
        )
    }

    private var insetViewportSize: CGSize {
        CGSize(
            width: max(viewportSize.width - contentInset * 2, 0),
            height: max(viewportSize.height - contentInset * 2, 0)
        )
    }

    func viewRect(from cropRect: CropRect) -> CGRect {
        let frame = imageFrame
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scaleX = frame.width / imageSize.width
        let scaleY = frame.height / imageSize.height
        return CGRect(
            x: frame.minX + cropRect.x * scaleX,
            y: frame.minY + cropRect.y * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )
    }

    func cropRect(from viewRect: CGRect) -> CropRect {
        let frame = imageFrame
        guard frame.width > 0, frame.height > 0 else {
            return CropRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        }
        let clipped = viewRect.intersection(frame)
        let scaleX = imageSize.width / frame.width
        let scaleY = imageSize.height / frame.height
        return CropRect(
            x: (clipped.minX - frame.minX) * scaleX,
            y: (clipped.minY - frame.minY) * scaleY,
            width: clipped.width * scaleX,
            height: clipped.height * scaleY
        ).clamped(to: imageSize)
    }
}
