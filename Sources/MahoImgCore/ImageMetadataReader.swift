import AppKit
import ImageIO
import PDFKit

enum ImageMetadataReader {
    static func pixelSize(for url: URL, pageIndex: Int = 0) -> CGSize? {
        guard let source = ImageSource.classify(url) else { return nil }
        switch source {
        case .pdf:
            return pdfPageSize(for: url, pageIndex: pageIndex)
        case .raster, .photoshop:
            return rasterPixelSize(for: url)
        }
    }

    static func pdfPageSize(for url: URL, pageIndex: Int) -> CGSize? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else {
            return nil
        }
        return page.bounds(for: .cropBox).size
    }

    @MainActor
    static func previewImage(for url: URL, pixelSize: CGSize, pageIndex: Int = 0) -> NSImage? {
        guard let source = ImageSource.classify(url) else { return nil }
        switch source {
        case .pdf:
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: pageIndex) else {
                return nil
            }
            return page.thumbnail(of: pixelSize, for: .cropBox)
        case .raster, .photoshop:
            if let cgImageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) {
                return NSImage(cgImage: cgImage, size: pixelSize)
            }
            return NSImage(contentsOf: url)
        }
    }

    private static func rasterPixelSize(for url: URL) -> CGSize? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Double,
           let height = properties[kCGImagePropertyPixelHeight] as? Double {
            return CGSize(width: width, height: height)
        }

        guard let image = NSImage(contentsOf: url) else { return nil }
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }
}
