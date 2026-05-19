import AppKit
import ImageIO
import PDFKit
import SwiftUI

struct PreviewPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if let job = state.selectedJob {
                CropPreview(job: job)
                    .padding(20)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("画像ファイルまたはフォルダをこのウィンドウへドロップ")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct CropPreview: View {
    @ObservedObject var job: ImageJob

    var body: some View {
        CropCanvas(job: job)
    }
}

private enum CropDragAction {
    case move
    case resize(ResizeAnchor)
}

private struct CropInteractionOverlay: View {
    @ObservedObject var job: ImageJob
    let mapper: PreviewMapper
    @State private var startRect: CropRect?
    @State private var action: CropDragAction?

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.001))
            .contentShape(Rectangle())
            .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if startRect == nil {
                    startRect = job.cropRect
                    action = dragAction(at: value.startLocation)
                }
                guard let startRect, let action else { return }
                guard mapper.imageFrame.width > 0, mapper.imageFrame.height > 0 else { return }
                let scaleX = job.pixelSize.width / mapper.imageFrame.width
                let scaleY = job.pixelSize.height / mapper.imageFrame.height
                let dx = value.translation.width * scaleX
                let dy = value.translation.height * scaleY

                switch action {
                case .move:
                    job.cropRect = CropRect(
                        x: startRect.x + dx,
                        y: startRect.y + dy,
                        width: startRect.width,
                        height: startRect.height
                    ).clamped(to: job.pixelSize)
                case .resize(let anchor):
                    job.cropRect = anchor.resized(rect: startRect, dx: dx, dy: dy).clamped(to: job.pixelSize)
                }
            }
            .onEnded { _ in
                startRect = nil
                action = nil
            }
    }

    private func dragAction(at point: CGPoint) -> CropDragAction? {
        let cropFrame = mapper.viewRect(from: job.cropRect)
        let hitSize = 24.0
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
}

private extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

private struct CropCanvas: NSViewRepresentable {
    @ObservedObject var job: ImageJob

    func makeNSView(context: Context) -> CropCanvasView {
        CropCanvasView()
    }

    func updateNSView(_ nsView: CropCanvasView, context: Context) {
        nsView.job = job
        nsView.image = Self.previewImage(for: job)
        nsView.needsDisplay = true
    }

    private static func previewImage(for job: ImageJob) -> NSImage? {
        if ImageProcessor.isPDFDocument(job.inputURL) {
            return pdfPreviewImage(for: job)
        }

        if let source = CGImageSourceCreateWithURL(job.inputURL as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return NSImage(cgImage: cgImage, size: job.pixelSize)
        }

        return NSImage(contentsOf: job.inputURL)
    }

    private static func pdfPreviewImage(for job: ImageJob) -> NSImage? {
        guard let document = PDFDocument(url: job.inputURL),
              let page = document.page(at: job.pageIndex) else {
            return nil
        }

        return page.thumbnail(of: job.pixelSize, for: .cropBox)
    }
}

@MainActor
private final class CropCanvasView: NSView {
    var job: ImageJob?
    var image: NSImage?
    private var action: CropDragAction?
    private var startPoint: CGPoint = .zero
    private var startRect: CropRect?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let job, let image else { return }

        let mapper = PreviewMapper(imageSize: job.pixelSize, viewportSize: bounds.size)
        let imageFrame = mapper.imageFrame
        let cropFrame = mapper.viewRect(from: job.cropRect)

        NSGraphicsContext.current?.imageInterpolation = .high
        drawPreviewImage(image, in: imageFrame, verticallyFlipped: ImageProcessor.isPhotoshopDocument(job.inputURL))

        let dimPath = NSBezierPath(rect: imageFrame)
        dimPath.append(NSBezierPath(rect: cropFrame))
        dimPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.22).setFill()
        dimPath.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(rect: cropFrame).fill()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: cropFrame)
        border.lineWidth = 2
        border.stroke()

        for point in cropHandlePoints(cropFrame) {
            drawHandle(at: point)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let job else { return }
        startPoint = convert(event.locationInWindow, from: nil)
        startRect = job.cropRect
        action = dragAction(at: startPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let job, let startRect, let action else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mapper = PreviewMapper(imageSize: job.pixelSize, viewportSize: bounds.size)
        guard mapper.imageFrame.width > 0, mapper.imageFrame.height > 0 else { return }

        let scaleX = job.pixelSize.width / mapper.imageFrame.width
        let scaleY = job.pixelSize.height / mapper.imageFrame.height
        let dx = (point.x - startPoint.x) * scaleX
        let dy = (point.y - startPoint.y) * scaleY

        switch action {
        case .move:
            job.cropRect = CropRect(
                x: startRect.x + dx,
                y: startRect.y + dy,
                width: startRect.width,
                height: startRect.height
            ).clamped(to: job.pixelSize)
        case .resize(let anchor):
            job.cropRect = anchor.resized(rect: startRect, dx: dx, dy: dy).clamped(to: job.pixelSize)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        action = nil
        startRect = nil
    }

    private func dragAction(at point: CGPoint) -> CropDragAction? {
        guard let job else { return nil }
        let mapper = PreviewMapper(imageSize: job.pixelSize, viewportSize: bounds.size)
        let cropFrame = mapper.viewRect(from: job.cropRect)
        let hitSize = 24.0

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

    private func cropHandlePoints(_ cropFrame: CGRect) -> [CGPoint] {
        [
            CGPoint(x: cropFrame.minX, y: cropFrame.minY),
            CGPoint(x: cropFrame.maxX, y: cropFrame.minY),
            CGPoint(x: cropFrame.minX, y: cropFrame.maxY),
            CGPoint(x: cropFrame.maxX, y: cropFrame.maxY)
        ]
    }

    private func drawHandle(at point: CGPoint) {
        let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
        let handle = NSBezierPath(ovalIn: rect)
        NSColor.controlAccentColor.setFill()
        handle.fill()
        NSColor.white.setStroke()
        handle.lineWidth = 1
        handle.stroke()
    }

    private func drawPreviewImage(_ image: NSImage, in imageFrame: CGRect, verticallyFlipped: Bool) {
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

struct CropBox: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.06))
            .overlay {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
    }
}

struct ResizeHandle: View {
    let position: CGPoint

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.001))
            .frame(width: 34, height: 34)
            .overlay {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
            }
            .position(position)
            .contentShape(Rectangle())
    }
}

struct CropMask: Shape {
    let imageFrame: CGRect
    let cropFrame: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(imageFrame)
        path.addRect(cropFrame)
        return path
    }
}

enum ResizeAnchor {
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
