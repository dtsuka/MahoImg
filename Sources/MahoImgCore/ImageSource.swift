import Foundation
import UniformTypeIdentifiers

enum ImageSource: Equatable {
    case raster(URL)
    case photoshop(URL)
    case pdf(URL)

    static let supportedExtensions = Set([
        "jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "psd", "psb", "pdf"
    ])

    static let selectableContentTypes: [UTType] = {
        let explicitTypes = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        return [.image, .pdf, .folder] + explicitTypes
    }()

    static func classify(_ url: URL) -> ImageSource? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf(url)
        case "psd", "psb":
            return .photoshop(url)
        case let ext where supportedExtensions.contains(ext):
            return .raster(url)
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .raster(let url), .photoshop(let url), .pdf(let url):
            return url
        }
    }

    var requiresPDFRasterization: Bool {
        if case .pdf = self { return true }
        return false
    }

    var drawsVerticallyFlipped: Bool {
        if case .photoshop = self { return true }
        return false
    }

    var magickInputPath: String {
        switch self {
        case .photoshop(let url):
            return "\(url.path)[0]"
        case .raster(let url), .pdf(let url):
            return url.path
        }
    }
}
