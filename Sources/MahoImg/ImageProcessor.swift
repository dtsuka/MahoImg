import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessorError: LocalizedError {
    case missingMagick
    case invalidOutputFolder
    case pdfRenderFailed
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingMagick:
            "/opt/homebrew/bin/magick が見つかりません。Homebrew版 ImageMagick をインストールしてください。"
        case .invalidOutputFolder:
            "保存先フォルダが見つかりません。"
        case .pdfRenderFailed:
            "PDFページの読み込みに失敗しました。"
        case .processFailed(let message):
            message
        }
    }
}

struct ImageProcessor {
    static let magickPath = "/opt/homebrew/bin/magick"

    static let supportedExtensions = Set(["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "psd", "psb", "pdf"])
    static let selectableContentTypes: [UTType] = {
        let explicitTypes = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        return [.image, .pdf, .folder] + explicitTypes
    }()

    static func isSupportedImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func isPhotoshopDocument(_ url: URL) -> Bool {
        ["psd", "psb"].contains(url.pathExtension.lowercased())
    }

    static func isPDFDocument(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    static func needsPDFRasterization(_ url: URL) -> Bool {
        isPDFDocument(url)
    }

    static func inputArgument(for inputURL: URL, pageIndex: Int = 0) -> String {
        if isPhotoshopDocument(inputURL) {
            return "\(inputURL.path)[0]"
        }
        return inputURL.path
    }

    static func outputURL(
        for inputURL: URL,
        settings: ConversionSettings,
        pageIndex: Int = 0,
        pageCount: Int = 1,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) throws -> URL {
        let folder: URL
        switch settings.saveLocation {
        case .original:
            folder = inputURL.deletingLastPathComponent()
        case .chosenFolder:
            guard !settings.chosenFolderPath.isEmpty else { throw ImageProcessorError.invalidOutputFolder }
            folder = URL(fileURLWithPath: settings.chosenFolderPath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: folder.path) else { throw ImageProcessorError.invalidOutputFolder }
        }

        let base = inputURL.deletingPathExtension().lastPathComponent
        let pageSuffix = pageCount > 1 ? String(format: "_p%03d", pageIndex + 1) : ""
        let name = "\(settings.prefix)\(base)\(pageSuffix)\(settings.suffix)"
        let ext = settings.outputFormat.fileExtension
        let proposed = folder.appendingPathComponent(name).appendingPathExtension(ext)

        if settings.conflictAction == .overwrite || !fileExists(proposed) {
            return proposed
        }

        for index in 1...9999 {
            let candidate = folder.appendingPathComponent("\(name)_\(index)").appendingPathExtension(ext)
            if !fileExists(candidate) {
                return candidate
            }
        }
        return proposed
    }

    static func arguments(inputURL: URL, outputURL: URL, settings: ConversionSettings, cropRect: CropRect, pageIndex: Int = 0) -> [String] {
        var args = [inputArgument(for: inputURL, pageIndex: pageIndex), "-auto-orient"]
        let crop = cropRect.clamped(to: CGSize(width: max(cropRect.x + cropRect.width, cropRect.width), height: max(cropRect.y + cropRect.height, cropRect.height)))
        if crop.width > 0, crop.height > 0 {
            args += [
                "-crop",
                "\(Int(crop.width.rounded()))x\(Int(crop.height.rounded()))+\(Int(crop.x.rounded()))+\(Int(crop.y.rounded()))",
                "+repage"
            ]
        }

        let width = max(settings.targetWidth, 1)
        let height = max(settings.targetHeight, 1)
        switch settings.resizeMode {
        case .none:
            break
        case .fit:
            args += ["-resize", "\(width)x\(height)"]
        case .fillCrop:
            args += ["-resize", "\(width)x\(height)^", "-gravity", "center", "-extent", "\(width)x\(height)"]
        case .width:
            args += ["-resize", "\(width)"]
        case .height:
            args += ["-resize", "x\(height)"]
        case .exact:
            args += ["-resize", "\(width)x\(height)!"]
        }

        if settings.paddingEnabled, settings.paddingPixels > 0 {
            args += ["-bordercolor", settings.paddingColor.value, "-border", "\(settings.paddingPixels)"]
        }

        switch settings.outputFormat {
        case .jpeg, .webp:
            args += ["-quality", "\(min(max(settings.quality, 1), 100))"]
        case .png:
            break
        }

        args.append(outputURL.path)
        return args
    }

    static func run(inputURL: URL, outputURL: URL, settings: ConversionSettings, cropRect: CropRect, pageIndex: Int = 0) async throws {
        guard FileManager.default.isExecutableFile(atPath: magickPath) else {
            throw ImageProcessorError.missingMagick
        }
        let rasterizedInputURL = try needsPDFRasterization(inputURL) ? rasterizedPDFInputURL(inputURL, pageIndex: pageIndex) : nil
        let processInputURL = rasterizedInputURL ?? inputURL

        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: magickPath)
            process.arguments = arguments(inputURL: processInputURL, outputURL: outputURL, settings: settings, cropRect: cropRect)

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.terminationHandler = { process in
                if let rasterizedInputURL {
                    try? FileManager.default.removeItem(at: rasterizedInputURL)
                }
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8) ?? "ImageMagick failed."
                    continuation.resume(throwing: ImageProcessorError.processFailed(message))
                }
            }

            do {
                try process.run()
            } catch {
                if let rasterizedInputURL {
                    try? FileManager.default.removeItem(at: rasterizedInputURL)
                }
                continuation.resume(throwing: error)
            }
        }
    }

    private static func rasterizedPDFInputURL(_ inputURL: URL, pageIndex: Int) throws -> URL {
        guard let document = CGPDFDocument(inputURL as CFURL),
              let page = document.page(at: pageIndex + 1) else {
            throw ImageProcessorError.pdfRenderFailed
        }

        let bounds = page.getBoxRect(.mediaBox)
        let width = max(1, Int(bounds.width.rounded(.up)))
        let height = max(1, Int(bounds.height.rounded(.up)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageProcessorError.pdfRenderFailed
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(page)

        guard let image = context.makeImage() else {
            throw ImageProcessorError.pdfRenderFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MahoImg-\(UUID().uuidString)")
            .appendingPathExtension("png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageProcessorError.pdfRenderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.pdfRenderFailed
        }
        return url
    }
}
