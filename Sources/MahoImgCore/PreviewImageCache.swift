import AppKit
import Foundation

@MainActor
enum PreviewImageCache {
    private struct CacheKey: Hashable {
        let url: URL
        let pageIndex: Int
        let width: Int
        let height: Int
    }

    private static var cache: [CacheKey: NSImage] = [:]

    static func image(for job: ImageJob) -> NSImage? {
        let key = CacheKey(
            url: job.inputURL,
            pageIndex: job.pageIndex,
            width: Int(job.pixelSize.width.rounded()),
            height: Int(job.pixelSize.height.rounded())
        )
        if let cached = cache[key] {
            return cached
        }
        guard let image = ImageMetadataReader.previewImage(
            for: job.source,
            pixelSize: job.pixelSize,
            pageIndex: job.pageIndex
        ) else {
            return nil
        }
        cache[key] = image
        return image
    }

    static func clear() {
        cache.removeAll()
    }
}
