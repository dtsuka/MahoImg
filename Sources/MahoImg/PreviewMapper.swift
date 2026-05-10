import CoreGraphics
import Foundation

struct PreviewMapper: Equatable {
    let imageSize: CGSize
    let viewportSize: CGSize

    var imageFrame: CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return .zero
        }
        let scale = min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (viewportSize.width - width) / 2,
            y: (viewportSize.height - height) / 2,
            width: width,
            height: height
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

