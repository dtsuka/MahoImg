import AppKit
import CoreGraphics
import Foundation
import PDFKit
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

    func testSetOriginXAdjustsWidthWhenExceedingImageBounds() {
        let imageSize = CGSize(width: 200, height: 100)
        var rect = CropRect(x: 0, y: 0, width: 180, height: 80)
        rect.setOriginX(50, in: imageSize)
        XCTAssertEqual(rect.x, 50, accuracy: 0.001)
        XCTAssertEqual(rect.width, 150, accuracy: 0.001)
    }

    func testSetWidthRespectsMinimumAndImageBounds() {
        let imageSize = CGSize(width: 200, height: 100)
        var rect = CropRect(x: 10, y: 0, width: 100, height: 80)
        rect.setWidth(300, in: imageSize)
        XCTAssertEqual(rect.width, 190, accuracy: 0.001)
    }
}

final class CropInteractionTests: XCTestCase {
    func testDragActionDetectsMoveInsideCropFrame() {
        let mapper = PreviewMapper(imageSize: CGSize(width: 400, height: 400), viewportSize: CGSize(width: 400, height: 400))
        let cropRect = CropRect(x: 100, y: 100, width: 200, height: 200)
        let cropFrame = mapper.viewRect(from: cropRect)
        let center = CGPoint(x: cropFrame.midX, y: cropFrame.midY)

        XCTAssertEqual(CropInteraction.dragAction(at: center, cropRect: cropRect, mapper: mapper), .move)
    }

    func testUpdatedCropRectMovesWithinImageBounds() {
        let imageSize = CGSize(width: 400, height: 400)
        let startRect = CropRect(x: 100, y: 100, width: 200, height: 200)
        let updated = CropInteraction.updatedCropRect(
            action: .move,
            startRect: startRect,
            dx: 50,
            dy: -20,
            imageSize: imageSize
        )
        XCTAssertEqual(updated.x, 150, accuracy: 0.001)
        XCTAssertEqual(updated.y, 80, accuracy: 0.001)
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

@MainActor
final class AppStateTests: XCTestCase {
    func testAddURLsCanActivateNewlyAddedImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.png")
        let secondURL = directory.appendingPathComponent("second.png")
        try writeTestPNG(to: firstURL)
        try writeTestPNG(to: secondURL)

        let state = makeState()
        state.addURLs([firstURL])
        let firstSelectedID = try XCTUnwrap(state.selectedJobIDs.first)

        state.selectJobIDs(state.addURLs([secondURL]))

        XCTAssertEqual(state.selectedJobIDs.count, 1)
        XCTAssertFalse(state.selectedJobIDs.contains(firstSelectedID))
        XCTAssertEqual(state.selectedJob?.inputURL, secondURL)
    }

    func testAddURLsCanActivateExistingImageWhenDroppedAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.png")
        let secondURL = directory.appendingPathComponent("second.png")
        try writeTestPNG(to: firstURL)
        try writeTestPNG(to: secondURL)

        let state = makeState()
        state.addURLs([firstURL])
        state.selectJobIDs(state.addURLs([secondURL]))

        state.selectJobIDs(state.addURLs([firstURL]))

        XCTAssertEqual(state.jobs.count, 2)
        XCTAssertEqual(state.selectedJobIDs.count, 1)
        XCTAssertEqual(state.selectedJob?.inputURL, firstURL)
    }

    func testAddURLsCanActivateMultipleDroppedImages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.png")
        let secondURL = directory.appendingPathComponent("second.png")
        try writeTestPNG(to: firstURL)
        try writeTestPNG(to: secondURL)

        let state = makeState()
        state.selectJobIDs(state.addURLs([firstURL, secondURL]))

        XCTAssertEqual(state.selectedJobs.map(\.inputURL), [firstURL, secondURL])
    }

    func testSelectedJobsKeepsListOrderForMultipleSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.png")
        let secondURL = directory.appendingPathComponent("second.png")
        let thirdURL = directory.appendingPathComponent("third.png")
        try writeTestPNG(to: firstURL)
        try writeTestPNG(to: secondURL)
        try writeTestPNG(to: thirdURL)

        let state = makeState()
        state.addURLs([firstURL, secondURL, thirdURL])
        let secondID = try XCTUnwrap(state.jobs.first { $0.inputURL == secondURL }?.id)
        let thirdID = try XCTUnwrap(state.jobs.first { $0.inputURL == thirdURL }?.id)

        state.selectedJobIDs = [thirdID, secondID]

        XCTAssertEqual(state.selectedJobs.map(\.inputURL), [secondURL, thirdURL])
        if case .multiple(let jobs) = state.selectionMode {
            XCTAssertEqual(jobs.map(\.inputURL), [secondURL, thirdURL])
        } else {
            XCTFail("Expected multiple selection mode")
        }
        XCTAssertNil(state.selectedJob)
    }

    func testResetCropForSelectedIgnoresMultipleSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.png")
        let secondURL = directory.appendingPathComponent("second.png")
        try writeTestPNG(to: firstURL)
        try writeTestPNG(to: secondURL)

        let state = makeState()
        state.addURLs([firstURL, secondURL])
        let firstJob = try XCTUnwrap(state.jobs.first { $0.inputURL == firstURL })
        let secondJob = try XCTUnwrap(state.jobs.first { $0.inputURL == secondURL })
        firstJob.cropRect = CropRect(x: 10, y: 10, width: 50, height: 50)
        secondJob.cropRect = CropRect(x: 20, y: 20, width: 60, height: 60)

        state.selectJobIDs([firstJob.id, secondJob.id])
        state.resetCropForSelected()

        XCTAssertEqual(firstJob.cropRect, CropRect(x: 10, y: 10, width: 50, height: 50))
        XCTAssertEqual(secondJob.cropRect, CropRect(x: 20, y: 20, width: 60, height: 60))
    }

    func testRemoveSelectedDeletesAllSelectedImages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.png")
        let secondURL = directory.appendingPathComponent("second.png")
        let thirdURL = directory.appendingPathComponent("third.png")
        try writeTestPNG(to: firstURL)
        try writeTestPNG(to: secondURL)
        try writeTestPNG(to: thirdURL)

        let state = makeState()
        state.addURLs([firstURL, secondURL, thirdURL])
        let firstID = try XCTUnwrap(state.jobs.first { $0.inputURL == firstURL }?.id)
        let thirdID = try XCTUnwrap(state.jobs.first { $0.inputURL == thirdURL }?.id)

        state.selectedJobIDs = [firstID, thirdID]
        state.removeSelected()

        XCTAssertEqual(state.jobs.map(\.inputURL), [secondURL])
        XCTAssertEqual(state.selectedJob?.inputURL, secondURL)
    }

    func testStoredSourceOnImageJob() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pngURL = directory.appendingPathComponent("photo.png")
        try writeTestPNG(to: pngURL)

        let state = makeState()
        state.addURLs([pngURL])
        let job = try XCTUnwrap(state.jobs.first)
        XCTAssertEqual(job.source, .raster(pngURL))
    }

    func testSetOutputFolderSelectsExistingDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = makeState()

        XCTAssertTrue(state.setOutputFolder(directory))
        XCTAssertEqual(state.settings.chosenFolderPath, directory.path)
        XCTAssertEqual(state.settings.saveLocation, .chosenFolder)
    }

    func testSetOutputFolderIgnoresFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("not-folder.txt")
        try Data().write(to: fileURL)
        let state = makeState()
        state.settings.chosenFolderPath = "/tmp/existing-output"
        state.settings.saveLocation = .original

        XCTAssertFalse(state.setOutputFolder(fileURL))
        XCTAssertEqual(state.settings.chosenFolderPath, "/tmp/existing-output")
        XCTAssertEqual(state.settings.saveLocation, .original)
    }

    private func makeState() -> AppState {
        AppState(settingsStorage: .ephemeral())
    }

    private func writeTestPNG(to url: URL) throws {
        let image = NSImage(size: CGSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()

        let data = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: data))
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}

final class ImageSourceTests: XCTestCase {
    func testClassifiesPDFAndPhotoshopDocuments() {
        XCTAssertEqual(
            ImageSource.classify(URL(fileURLWithPath: "/tmp/catalog.pdf")),
            .pdf(URL(fileURLWithPath: "/tmp/catalog.pdf"))
        )
        XCTAssertEqual(
            ImageSource.classify(URL(fileURLWithPath: "/tmp/layered.psd")),
            .photoshop(URL(fileURLWithPath: "/tmp/layered.psd"))
        )
    }

    func testArgumentsClampCropToImageSize() {
        var settings = ConversionSettings()
        settings.outputFormat = .webp
        settings.resizeMode = .none

        let args = ImageProcessor.arguments(
            inputURL: URL(fileURLWithPath: "/tmp/in.jpg"),
            outputURL: URL(fileURLWithPath: "/tmp/out.webp"),
            settings: settings,
            cropRect: CropRect(x: 0, y: 0, width: 500, height: 400),
            imageSize: CGSize(width: 300, height: 200),
            source: .raster(URL(fileURLWithPath: "/tmp/in.jpg"))
        )

        XCTAssertTrue(args.contains("-crop"))
        XCTAssertTrue(args.contains("300x200+0+0"))
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
        XCTAssertNotNil(ImageSource.classify(URL(fileURLWithPath: "/tmp/design.psd")))
        XCTAssertNotNil(ImageSource.classify(URL(fileURLWithPath: "/tmp/large-design.psb")))
    }

    func testSupportsPDFDocuments() {
        XCTAssertNotNil(ImageSource.classify(URL(fileURLWithPath: "/tmp/catalog.pdf")))
    }

    func testPhotoshopDocumentUsesFirstImageOnly() {
        XCTAssertEqual(
            ImageProcessor.inputArgument(for: .photoshop(URL(fileURLWithPath: "/tmp/layered.psd"))),
            "/tmp/layered.psd[0]"
        )
    }

    func testPDFDocumentsAreRasterizedBeforeImageMagick() {
        let source = ImageSource.classify(URL(fileURLWithPath: "/tmp/catalog.pdf"))
        XCTAssertTrue(source?.requiresPDFRasterization ?? false)
    }

    func testPDFRasterizationUsesHighResolutionScale() {
        XCTAssertEqual(ImageProcessor.pdfRasterizationScale, 600.0 / 72.0, accuracy: 0.001)
    }

    func testPDFRasterizationDrawsFreeTextAnnotations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pdfURL = directory.appendingPathComponent("annotation.pdf")
        let pageSize = CGSize(width: 200, height: 200)
        let image = NSImage(size: pageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: pageSize).fill()
        image.unlockFocus()

        guard let page = PDFPage(image: image) else {
            return XCTFail("Failed to create test PDF page")
        }

        let annotation = PDFAnnotation(
            bounds: CGRect(x: 60, y: 70, width: 80, height: 60),
            forType: .freeText,
            withProperties: nil
        )
        annotation.contents = "A"
        annotation.font = .boldSystemFont(ofSize: 48)
        annotation.fontColor = .black
        annotation.color = .clear
        page.addAnnotation(annotation)

        let document = PDFDocument()
        document.insert(page, at: 0)
        XCTAssertTrue(document.write(to: pdfURL))

        let rasterizedURL = try ImageProcessor.rasterizedPDFInput(pdfURL, pageIndex: 0, scale: 2)
        defer { try? FileManager.default.removeItem(at: rasterizedURL) }

        let rasterizedData = try Data(contentsOf: rasterizedURL)
        guard let imageRep = NSBitmapImageRep(data: rasterizedData) else {
            return XCTFail("Failed to read rasterized PDF image")
        }

        var darkPixelCount = 0
        for y in 0..<imageRep.pixelsHigh {
            for x in 0..<imageRep.pixelsWide {
                guard let color = imageRep.colorAt(x: x, y: y) else { continue }
                if color.redComponent < 0.2, color.greenComponent < 0.2, color.blueComponent < 0.2, color.alphaComponent > 0.8 {
                    darkPixelCount += 1
                }
            }
        }

        XCTAssertGreaterThan(darkPixelCount, 100)
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

    func testOutputURLRejectsChosenFilePath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("not-folder")
        try Data().write(to: fileURL)

        var settings = ConversionSettings()
        settings.saveLocation = .chosenFolder
        settings.chosenFolderPath = fileURL.path

        XCTAssertThrowsError(
            try ImageProcessor.outputURL(for: URL(fileURLWithPath: "/tmp/photo.jpg"), settings: settings)
        ) { error in
            guard let processorError = error as? ImageProcessorError,
                  case .invalidOutputFolder = processorError else {
                return XCTFail("Expected invalid output folder, got \(error)")
            }
        }
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
            cropRect: CropRect(x: 10, y: 20, width: 500, height: 400),
            imageSize: CGSize(width: 1920, height: 1080),
            source: .raster(URL(fileURLWithPath: "/tmp/in.jpg"))
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

        let rasterURL = URL(fileURLWithPath: "/tmp/rasterized.pdf-page.png")
        let args = ImageProcessor.arguments(
            inputURL: rasterURL,
            outputURL: URL(fileURLWithPath: "/tmp/out.jpg"),
            settings: settings,
            cropRect: CropRect(x: 0, y: 0, width: 4167, height: 5896),
            imageSize: CGSize(width: 4167, height: 5896),
            source: .raster(rasterURL),
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

        let rasterURL = URL(fileURLWithPath: "/tmp/rasterized.pdf-page.png")
        let args = ImageProcessor.arguments(
            inputURL: rasterURL,
            outputURL: URL(fileURLWithPath: "/tmp/out.jpg"),
            settings: settings,
            cropRect: CropRect(x: 0, y: 0, width: 5102, height: 7158),
            imageSize: CGSize(width: 5102, height: 7158),
            source: .raster(rasterURL)
        )

        XCTAssertFalse(args.contains("-trim"))
    }
}
