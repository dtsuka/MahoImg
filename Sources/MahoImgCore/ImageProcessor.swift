import AppKit
import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers

enum ImageProcessorError: LocalizedError {
    case missingMagick
    case invalidOutputFolder
    case pdfRenderFailed
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingMagick:
            "ImageMagick の magick コマンドが見つかりません。ImageMagick をインストールしてください。"
        case .invalidOutputFolder:
            "保存先フォルダが見つかりません。保存先を選び直してください。"
        case .pdfRenderFailed:
            "PDFページの読み込みに失敗しました。"
        case .processFailed(let message):
            message
        }
    }
}

struct ImageProcessor {
    static let pdfRasterizationDPI = 600.0
    private static let pdfPointsPerInch = 72.0
    static var magickPath: String { resolveMagickPath() }
    static let magickInstallGuide = """
    WebP 書き出しなどの変換処理には ImageMagick が必要です。Homebrew を使っている場合は、ターミナルで次を実行してください。

    brew install imagemagick

    インストール後、次のコマンドで確認できます。

    magick -version

    MahoImg は /opt/homebrew/bin/magick、/usr/local/bin/magick、PATH 上の magick の順に ImageMagick を探します。Homebrew が入っていない場合は、先に Homebrew をインストールしてください。
    """

    static let supportedExtensions = Set(["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "psd", "psb", "pdf"])
    static let selectableContentTypes: [UTType] = {
        let explicitTypes = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        return [.image, .pdf, .folder] + explicitTypes
    }()

    static func isSupportedImage(_ url: URL) -> Bool {
        ImageSource.classify(url) != nil
    }

    static func isPhotoshopDocument(_ url: URL) -> Bool {
        if case .photoshop = ImageSource.classify(url) { return true }
        return false
    }

    static func isPDFDocument(_ url: URL) -> Bool {
        if case .pdf = ImageSource.classify(url) { return true }
        return false
    }

    static var pdfRasterizationScale: Double {
        pdfRasterizationDPI / pdfPointsPerInch
    }

    static func scaledCropRect(_ cropRect: CropRect, by scale: Double) -> CropRect {
        CropRect(
            x: cropRect.x * scale,
            y: cropRect.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
    }

    static func isMagickAvailable(path: String? = nil, fileManager: FileManager = .default) -> Bool {
        fileManager.isExecutableFile(atPath: path ?? magickPath)
    }

    static func resolveMagickPath(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        commonPaths: [String] = [
            "/opt/homebrew/bin/magick",
            "/usr/local/bin/magick"
        ]
    ) -> String {
        if let path = commonPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }

        let pathDirectories = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        for directory in pathDirectories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("magick").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return commonPaths.first ?? "/opt/homebrew/bin/magick"
    }

    static func inputArgument(for inputURL: URL) -> String {
        ImageSource.classify(inputURL)?.magickInputPath ?? inputURL.path
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

    static func arguments(
        inputURL: URL,
        outputURL: URL,
        settings: ConversionSettings,
        cropRect: CropRect,
        imageSize: CGSize,
        trimsWhitespace: Bool = false
    ) -> [String] {
        var args = [inputArgument(for: inputURL), "-auto-orient"]
        let crop = cropRect.clamped(to: imageSize)
        if crop.width > 0, crop.height > 0 {
            args += [
                "-crop",
                "\(Int(crop.width.rounded()))x\(Int(crop.height.rounded()))+\(Int(crop.x.rounded()))+\(Int(crop.y.rounded()))",
                "+repage"
            ]
        }
        if trimsWhitespace {
            args += ["-fuzz", "1%", "-trim", "+repage"]
        }

        let width = max(settings.targetWidth, 1)
        let height = max(settings.targetHeight, 1)
        switch settings.resizeMode {
        case .none:
            break
        case .fit:
            args += ["-filter", "Lanczos", "-resize", "\(width)x\(height)"]
        case .fillCrop:
            args += ["-filter", "Lanczos", "-resize", "\(width)x\(height)^", "-gravity", "center", "-extent", "\(width)x\(height)"]
        case .width:
            args += ["-filter", "Lanczos", "-resize", "\(width)"]
        case .height:
            args += ["-filter", "Lanczos", "-resize", "x\(height)"]
        case .exact:
            args += ["-filter", "Lanczos", "-resize", "\(width)x\(height)!"]
        }

        if settings.paddingEnabled, settings.paddingPixels > 0 {
            args += ["-bordercolor", settings.paddingColor.value, "-border", "\(settings.paddingPixels)"]
        }

        switch settings.outputFormat {
        case .jpeg:
            args += ["-strip", "-sampling-factor", "4:2:0", "-interlace", "Plane", "-quality", "\(min(max(settings.quality, 1), 100))"]
        case .webp:
            args += ["-quality", "\(min(max(settings.quality, 1), 100))"]
        case .png:
            break
        }

        args.append(outputURL.path)
        return args
    }

    static func run(
        inputURL: URL,
        outputURL: URL,
        settings: ConversionSettings,
        cropRect: CropRect,
        imageSize: CGSize,
        pageIndex: Int = 0
    ) async throws {
        guard FileManager.default.isExecutableFile(atPath: magickPath) else {
            throw ImageProcessorError.missingMagick
        }

        guard let source = ImageSource.classify(inputURL) else {
            throw ImageProcessorError.processFailed("サポートされていないファイル形式です。")
        }

        let pdfScale = pdfRasterizationScale
        let rasterizedInput = try source.requiresPDFRasterization
            ? rasterizedPDFInput(inputURL, pageIndex: pageIndex, scale: pdfScale)
            : nil
        let processInputURL = rasterizedInput ?? inputURL
        let processCropRect = rasterizedInput == nil ? cropRect : scaledCropRect(cropRect, by: pdfScale)
        let processImageSize: CGSize
        if rasterizedInput != nil {
            guard let rasterSize = rasterizedPDFPixelSize(for: inputURL, pageIndex: pageIndex, scale: pdfScale) else {
                throw ImageProcessorError.pdfRenderFailed
            }
            processImageSize = rasterSize
        } else {
            processImageSize = imageSize
        }
        let trimsWhitespace = rasterizedInput != nil && settings.pdfAutoTrimWhitespace

        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: magickPath)
            process.arguments = arguments(
                inputURL: processInputURL,
                outputURL: outputURL,
                settings: settings,
                cropRect: processCropRect,
                imageSize: processImageSize,
                trimsWhitespace: trimsWhitespace
            )

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.terminationHandler = { process in
                if let rasterizedInput {
                    try? FileManager.default.removeItem(at: rasterizedInput)
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
                if let rasterizedInput {
                    try? FileManager.default.removeItem(at: rasterizedInput)
                }
                continuation.resume(throwing: error)
            }
        }
    }

    static func rasterizedPDFPixelSize(for inputURL: URL, pageIndex: Int, scale: Double) -> CGSize? {
        guard let document = PDFDocument(url: inputURL),
              let page = document.page(at: pageIndex) else {
            return nil
        }
        let bounds = page.bounds(for: .cropBox)
        return CGSize(
            width: max(1, (bounds.width * scale).rounded(.up)),
            height: max(1, (bounds.height * scale).rounded(.up))
        )
    }

    static func rasterizedPDFInput(_ inputURL: URL, pageIndex: Int, scale: Double) throws -> URL {
        guard let document = PDFDocument(url: inputURL),
              let page = document.page(at: pageIndex) else {
            throw ImageProcessorError.pdfRenderFailed
        }

        let bounds = page.bounds(for: .cropBox)
        let width = max(1, Int((bounds.width * scale).rounded(.up)))
        let height = max(1, Int((bounds.height * scale).rounded(.up)))
        guard let imageRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
            let graphicsContext = NSGraphicsContext(bitmapImageRep: imageRep) else {
            throw ImageProcessorError.pdfRenderFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        let context = graphicsContext.cgContext
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)

        guard let data = imageRep.representation(using: .png, properties: [:]) else {
            throw ImageProcessorError.pdfRenderFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MahoImg-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try data.write(to: url, options: .atomic)
        return url
    }
}
