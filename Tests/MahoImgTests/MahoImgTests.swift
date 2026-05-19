import CoreGraphics
import Foundation
@testable import MahoImgCore
import XCTest

final class CropRectTests: XCTestCase {
    func testClampedNeverExceedsImageWhenImageSmallerThanMinimum() {
        let tiny = CGSize(width: 10, height: 8)
        let rect = CropRect(x: 0, y: 0, width: 4, height: 3)
        let clamped = rect.clamped(to: tiny, minimum: 16)
        XCTAssertEqual(clamped.width, 10, accuracy: 0.001)
        XCTAssertEqual(clamped.height, 8, accuracy: 0.001)
        XCTAssertEqual(clamped.x + clamped.width, 10, accuracy: 0.001)
        XCTAssertEqual(clamped.y + clamped.height, 8, accuracy: 0.001)
    }
}

final class PreviewMapperTests: XCTestCase {
    func testMapsLandscapeImageIntoLetterboxedViewport() {
        let mapper = PreviewMapper(imageSize: CGSize(width: 1600, height: 800), viewportSize: CGSize(width: 400, height: 400))

        XCTAssertEqual(mapper.imageFrame, CGRect(x: 0, y: 100, width: 400, height: 200))

        let viewRect = mapper.viewRect(from: CropRect(x: 400, y: 200, width: 800, height: 400))
        XCTAssertEqual(viewRect.origin.x, 100, accuracy: 0.001)
        XCTAssertEqual(viewRect.origin.y, 150, accuracy: 0.001)
        XCTAssertEqual(viewRect.width, 200, accuracy: 0.001)
        XCTAssertEqual(viewRect.height, 100, accuracy: 0.001)

        let cropRect = mapper.cropRect(from: viewRect)
        XCTAssertEqual(cropRect.x, 400, accuracy: 0.001)
        XCTAssertEqual(cropRect.y, 200, accuracy: 0.001)
        XCTAssertEqual(cropRect.width, 800, accuracy: 0.001)
        XCTAssertEqual(cropRect.height, 400, accuracy: 0.001)
    }

    func testMapsPortraitImageIntoPillarboxedViewport() {
        let mapper = PreviewMapper(imageSize: CGSize(width: 800, height: 1600), viewportSize: CGSize(width: 400, height: 400))

        XCTAssertEqual(mapper.imageFrame, CGRect(x: 100, y: 0, width: 200, height: 400))

        let cropRect = mapper.cropRect(from: CGRect(x: 150, y: 100, width: 100, height: 200))
        XCTAssertEqual(cropRect.x, 200, accuracy: 0.001)
        XCTAssertEqual(cropRect.y, 400, accuracy: 0.001)
        XCTAssertEqual(cropRect.width, 400, accuracy: 0.001)
        XCTAssertEqual(cropRect.height, 800, accuracy: 0.001)
    }
}

final class ImageProcessorTests: XCTestCase {
    func testResolvesMagickFromPathEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let magick = directory.appendingPathComponent("magick")
        try Data().write(to: magick)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: magick.path)

        XCTAssertEqual(
            ImageProcessor.resolveMagickPath(
                environment: ["PATH": directory.path],
                commonPaths: ["/definitely/not/a/real/magick"]
            ),
            magick.path
        )
    }

    func testResolvesMagickToDefaultFallbackWhenNotFound() {
        XCTAssertEqual(
            ImageProcessor.resolveMagickPath(
                environment: ["PATH": "/definitely/not/a/real/path"],
                commonPaths: ["/custom/fallback/magick"]
            ),
            "/custom/fallback/magick"
        )
    }

    func testResolvesMagickToHomebrewFallbackWhenNoCandidatesExist() {
        XCTAssertEqual(
            ImageProcessor.resolveMagickPath(
                environment: ["PATH": "/definitely/not/a/real/path"],
                commonPaths: []
            ),
            "/opt/homebrew/bin/magick"
        )
    }

    func testDetectsMissingMagickPath() {
        XCTAssertFalse(ImageProcessor.isMagickAvailable(path: "/definitely/not/a/real/magick"))
    }

    func testSupportsPhotoshopDocuments() {
        XCTAssertTrue(ImageProcessor.isSupportedImage(URL(fileURLWithPath: "/tmp/design.psd")))
        XCTAssertTrue(ImageProcessor.isSupportedImage(URL(fileURLWithPath: "/tmp/large-design.psb")))
    }

    func testSupportsPDFDocuments() {
        XCTAssertTrue(ImageProcessor.isSupportedImage(URL(fileURLWithPath: "/tmp/catalog.pdf")))
    }

    func testPhotoshopDocumentUsesFirstImageOnly() {
        XCTAssertEqual(
            ImageProcessor.inputArgument(for: URL(fileURLWithPath: "/tmp/layered.psd")),
            "/tmp/layered.psd[0]"
        )
    }

    func testPDFDocumentsAreRasterizedBeforeImageMagick() {
        XCTAssertTrue(ImageProcessor.needsPDFRasterization(URL(fileURLWithPath: "/tmp/catalog.pdf")))
    }

    func testPDFRasterizationUsesHighResolutionScale() {
        XCTAssertEqual(ImageProcessor.pdfRasterizationScale, 600.0 / 72.0, accuracy: 0.001)
    }

    func testScalesCropRectForRasterizedPDF() {
        let cropRect = ImageProcessor.scaledCropRect(
            CropRect(x: 12, y: 24, width: 120, height: 80),
            by: 600.0 / 72.0
        )

        XCTAssertEqual(cropRect.x, 100, accuracy: 0.001)
        XCTAssertEqual(cropRect.y, 200, accuracy: 0.001)
        XCTAssertEqual(cropRect.width, 1000, accuracy: 0.001)
        XCTAssertEqual(cropRect.height, 666.667, accuracy: 0.001)
    }

    func testOutputURLRenamesConflicts() throws {
        var settings = ConversionSettings()
        settings.outputFormat = .webp
        settings.prefix = "th_"
        settings.suffix = "_small"
        settings.conflictAction = .rename

        let input = URL(fileURLWithPath: "/tmp/photo.jpg")
        let existing = Set([
            "/tmp/th_photo_small.webp",
            "/tmp/th_photo_small_1.webp"
        ])

        let output = try ImageProcessor.outputURL(for: input, settings: settings) { url in
            existing.contains(url.path)
        }

        XCTAssertEqual(output.path, "/tmp/th_photo_small_2.webp")
    }

    func testOutputURLAddsPageSuffixForMultiPageDocuments() throws {
        var settings = ConversionSettings()
        settings.outputFormat = .webp

        let output = try ImageProcessor.outputURL(
            for: URL(fileURLWithPath: "/tmp/catalog.pdf"),
            settings: settings,
            pageIndex: 2,
            pageCount: 12
        )

        XCTAssertEqual(output.path, "/tmp/catalog_p003.webp")
    }

    func testBuildsWebPFitArgumentsWithQualityAndPadding() {
        var settings = ConversionSettings()
        settings.outputFormat = .webp
        settings.quality = 70
        settings.resizeMode = .fit
        settings.targetWidth = 300
        settings.targetHeight = 200
        settings.paddingEnabled = true
        settings.paddingPixels = 8
        settings.paddingColor = ColorHex(value: "#ff00aa")

        let args = ImageProcessor.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/in.jpg"),
            outputURL: URL(fileURLWithPath: "/tmp/out.webp"),
            settings: settings,
            cropRect: CropRect(x: 10, y: 20, width: 500, height: 400)
        )

        XCTAssertEqual(args, [
            "/tmp/in.jpg",
            "-auto-orient",
            "-crop",
            "500x400+10+20",
            "+repage",
            "-filter",
            "Lanczos",
            "-resize",
            "300x200",
            "-bordercolor",
            "#ff00aa",
            "-border",
            "8",
            "-quality",
            "70",
            "/tmp/out.webp"
        ])
    }

    func testBuildsPDFRasterizedArgumentsWithWhitespaceTrimBeforeResize() {
        var settings = ConversionSettings()
        settings.outputFormat = .jpeg
        settings.resizeMode = .fit
        settings.targetWidth = 1200
        settings.targetHeight = 1200

        let args = ImageProcessor.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/rasterized.pdf-page.png"),
            outputURL: URL(fileURLWithPath: "/tmp/out.jpg"),
            settings: settings,
            cropRect: CropRect(x: 0, y: 0, width: 4167, height: 5896),
            trimsWhitespace: true
        )

        XCTAssertEqual(args, [
            "/tmp/rasterized.pdf-page.png",
            "-auto-orient",
            "-crop",
            "4167x5896+0+0",
            "+repage",
            "-fuzz",
            "1%",
            "-trim",
            "+repage",
            "-filter",
            "Lanczos",
            "-resize",
            "1200x1200",
            "-strip",
            "-sampling-factor",
            "4:2:0",
            "-interlace",
            "Plane",
            "-quality",
            "82",
            "/tmp/out.jpg"
        ])
    }

    func testBuildsPDFRasterizedArgumentsWithoutWhitespaceTrimByDefault() {
        var settings = ConversionSettings()
        settings.outputFormat = .jpeg
        settings.resizeMode = .fit
        settings.targetWidth = 1224
        settings.targetHeight = 1000

        let args = ImageProcessor.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/rasterized.pdf-page.png"),
            outputURL: URL(fileURLWithPath: "/tmp/out.jpg"),
            settings: settings,
            cropRect: CropRect(x: 0, y: 0, width: 5102, height: 7158)
        )

        XCTAssertFalse(args.contains("-trim"))
    }
}
