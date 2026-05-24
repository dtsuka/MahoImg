import AppKit
import SwiftUI

struct PreviewPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            switch state.selectionMode {
            case .multiple(let jobs):
                MultiSelectionPreview(jobs: jobs)
                    .padding(20)
            case .single(let job):
                CropPreview(job: job)
                    .padding(20)
            case .none:
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

private struct MultiSelectionPreview: View {
    let jobs: [ImageJob]
    private let maxPreviewCount = 12
    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("選択中: \(jobs.count)件")
                    .font(.headline)
                Spacer()
                if omittedCount > 0 {
                    Text("ほか\(omittedCount)件を省略")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(visibleJobs) { job in
                        SelectedJobPreviewTile(job: job)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var visibleJobs: ArraySlice<ImageJob> {
        jobs.prefix(maxPreviewCount)
    }

    private var omittedCount: Int {
        max(0, jobs.count - maxPreviewCount)
    }
}

private struct SelectedJobPreviewTile: View {
    @ObservedObject var job: ImageJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PreviewCanvas(job: job, mode: .thumbnail)
                .aspectRatio(1, contentMode: .fit)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }

            Text(job.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(job.displayName)
        }
    }
}

struct CropPreview: View {
    @ObservedObject var job: ImageJob

    var body: some View {
        PreviewCanvas(job: job, mode: .crop)
    }
}

private enum PreviewCanvasMode {
    case thumbnail
    case crop
}

private struct PreviewCanvas: NSViewRepresentable {
    @ObservedObject var job: ImageJob
    let mode: PreviewCanvasMode

    func makeNSView(context: Context) -> PreviewCanvasView {
        PreviewCanvasView(mode: mode)
    }

    func updateNSView(_ nsView: PreviewCanvasView, context: Context) {
        nsView.job = job
        nsView.image = PreviewImageCache.image(for: job)
        nsView.needsDisplay = true
    }
}

@MainActor
private final class PreviewCanvasView: NSView {
    let mode: PreviewCanvasMode
    var job: ImageJob?
    var image: NSImage?
    private var action: CropDragAction?
    private var startPoint: CGPoint = .zero
    private var startRect: CropRect?

    init(mode: PreviewCanvasMode) {
        self.mode = mode
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        mode == .crop
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        mode == .crop && bounds.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let job, let image else { return }

        let mapper = PreviewMapper(imageSize: job.pixelSize, viewportSize: bounds.size)
        let imageFrame = mapper.imageFrame

        NSGraphicsContext.current?.imageInterpolation = .high
        PreviewDrawing.drawImage(
            image,
            in: imageFrame,
            verticallyFlipped: job.source.drawsVerticallyFlipped
        )

        guard mode == .crop else { return }

        let cropFrame = mapper.viewRect(from: job.cropRect)

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
        guard mode == .crop, let job else { return }
        let mapper = PreviewMapper(imageSize: job.pixelSize, viewportSize: bounds.size)
        startPoint = convert(event.locationInWindow, from: nil)
        startRect = job.cropRect
        action = CropInteraction.dragAction(at: startPoint, cropRect: job.cropRect, mapper: mapper)
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .crop, let job, let startRect, let action else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mapper = PreviewMapper(imageSize: job.pixelSize, viewportSize: bounds.size)
        guard mapper.imageFrame.width > 0, mapper.imageFrame.height > 0 else { return }

        let scaleX = job.pixelSize.width / mapper.imageFrame.width
        let scaleY = job.pixelSize.height / mapper.imageFrame.height
        let dx = (point.x - startPoint.x) * scaleX
        let dy = (point.y - startPoint.y) * scaleY

        job.cropRect = CropInteraction.updatedCropRect(
            action: action,
            startRect: startRect,
            dx: dx,
            dy: dy,
            imageSize: job.pixelSize
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        action = nil
        startRect = nil
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
}
