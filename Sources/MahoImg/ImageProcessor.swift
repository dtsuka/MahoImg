import Foundation
import UniformTypeIdentifiers

enum ImageProcessorError: LocalizedError {
    case missingMagick
    case invalidOutputFolder
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingMagick:
            "/opt/homebrew/bin/magick が見つかりません。Homebrew版 ImageMagick をインストールしてください。"
        case .invalidOutputFolder:
            "保存先フォルダが見つかりません。"
        case .processFailed(let message):
            message
        }
    }
}

struct ImageProcessor {
    static let magickPath = "/opt/homebrew/bin/magick"

    static let supportedExtensions = Set(["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "psd", "psb"])
    static let selectableContentTypes: [UTType] = {
        let explicitTypes = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        return [.image, .folder] + explicitTypes
    }()

    static func isSupportedImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func isPhotoshopDocument(_ url: URL) -> Bool {
        ["psd", "psb"].contains(url.pathExtension.lowercased())
    }

    static func inputArgument(for inputURL: URL) -> String {
        if isPhotoshopDocument(inputURL) {
            return "\(inputURL.path)[0]"
        }
        return inputURL.path
    }

    static func outputURL(
        for inputURL: URL,
        settings: ConversionSettings,
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
        let name = "\(settings.prefix)\(base)\(settings.suffix)"
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

    static func arguments(inputURL: URL, outputURL: URL, settings: ConversionSettings, cropRect: CropRect) -> [String] {
        var args = [inputArgument(for: inputURL), "-auto-orient"]
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

    static func run(inputURL: URL, outputURL: URL, settings: ConversionSettings, cropRect: CropRect) async throws {
        guard FileManager.default.isExecutableFile(atPath: magickPath) else {
            throw ImageProcessorError.missingMagick
        }
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: magickPath)
            process.arguments = arguments(inputURL: inputURL, outputURL: outputURL, settings: settings, cropRect: cropRect)

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.terminationHandler = { process in
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
                continuation.resume(throwing: error)
            }
        }
    }
}
