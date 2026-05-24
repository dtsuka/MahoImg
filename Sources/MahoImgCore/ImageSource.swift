import Foundation

enum ImageSource: Equatable {
    case raster(URL)
    case photoshop(URL)
    case pdf(URL)

    static func classify(_ url: URL) -> ImageSource? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf(url)
        case "psd", "psb":
            return .photoshop(url)
        case let ext where ImageProcessor.supportedExtensions.contains(ext):
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

extension ImageJob {
    var source: ImageSource {
        ImageSource.classify(inputURL) ?? .raster(inputURL)
    }
}
