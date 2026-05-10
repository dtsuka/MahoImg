import CoreGraphics
import Foundation
@testable import MahoImg
import XCTest

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
}

