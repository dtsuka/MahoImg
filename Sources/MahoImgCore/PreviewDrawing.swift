import AppKit
import CoreGraphics

enum PreviewDrawing {
    static func drawImage(_ image: NSImage, in imageFrame: CGRect, verticallyFlipped: Bool) {
        guard verticallyFlipped else {
            image.draw(in: imageFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: imageFrame.minY + imageFrame.maxY)
        transform.scaleX(by: 1, yBy: -1)
        transform.concat()
        image.draw(in: imageFrame, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
}
