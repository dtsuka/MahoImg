import AppKit
import Foundation

enum OutputFormat: String, CaseIterable, Codable, Identifiable {
    case jpeg = "JPEG"
    case png = "PNG"
    case webp = "WebP"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .webp: "webp"
        }
    }
}

enum ResizeMode: String, CaseIterable, Codable, Identifiable {
    case none = "しない"
    case fit = "内接"
    case canvasFit = "キャンバスに内接"
    case fillCrop = "外接"
    case width = "幅指定"
    case height = "高さ指定"
    case exact = "幅高さ指定"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            "リサイズしない"
        case .fit:
            "最大サイズに収める"
        case .canvasFit:
            "キャンバスに内接（余白あり）"
        case .fillCrop:
            "キャンバスを埋める（切り抜き）"
        case .width:
            "幅を指定"
        case .height:
            "高さを指定"
        case .exact:
            "指定サイズに変形"
        }
    }

    var helpText: String {
        switch self {
        case .none:
            "元画像のピクセルサイズを維持します。"
        case .fit:
            "指定した最大幅・最大高さの内側に、縦横比を維持して画像全体を収めます。出力サイズは画像の比率に応じて変わります。"
        case .canvasFit:
            "指定したキャンバスの内側に、縦横比を維持して画像全体を収めます。余った部分は背景色で埋め、出力は必ず指定サイズになります。"
        case .fillCrop:
            "指定サイズを覆うまで縦横比を維持して拡大縮小し、はみ出した部分を中央で切り落とします。"
        case .width:
            "幅を指定値に合わせ、高さは縦横比から自動計算します。"
        case .height:
            "高さを指定値に合わせ、幅は縦横比から自動計算します。"
        case .exact:
            "指定した幅と高さに強制変形します。縦横比が変わる場合があります。"
        }
    }

    var widthLabel: String? {
        switch self {
        case .none, .height:
            nil
        case .fit:
            "最大幅"
        case .canvasFit:
            "キャンバス幅"
        case .fillCrop, .exact:
            "出力幅"
        case .width:
            "幅"
        }
    }

    var heightLabel: String? {
        switch self {
        case .none, .width:
            nil
        case .fit:
            "最大高さ"
        case .canvasFit:
            "キャンバス高さ"
        case .fillCrop, .exact:
            "出力高さ"
        case .height:
            "高さ"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "フィット" {
            self = .fit
            return
        }
        if value == "塗り足しクロップ" {
            self = .fillCrop
            return
        }
        guard let mode = ResizeMode(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown resize mode: \(value)")
        }
        self = mode
    }
}

enum SaveLocation: String, CaseIterable, Codable, Identifiable {
    case original = "元画像と同じ"
    case chosenFolder = "選択フォルダ"

    var id: String { rawValue }
}

enum NameConflictAction: String, CaseIterable, Codable, Identifiable {
    case rename = "連番リネーム"
    case overwrite = "上書き"

    var id: String { rawValue }
}

enum PreviewBackground: String, CaseIterable, Codable, Identifiable {
    case gray = "グレー"
    case white = "白"
    case black = "黒"
    case checkerboard = "チェッカー"

    var id: String { rawValue }
}

struct ColorHex: Codable, Equatable {
    var value: String

    static let white = ColorHex(value: "#ffffff")

    var nsColor: NSColor {
        let text = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard text.count == 6, let intValue = Int(text, radix: 16) else {
            return .white
        }
        let red = CGFloat((intValue >> 16) & 0xff) / 255
        let green = CGFloat((intValue >> 8) & 0xff) / 255
        let blue = CGFloat(intValue & 0xff) / 255
        return NSColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

struct CropRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static func full(size: CGSize) -> CropRect {
        CropRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    func clamped(to size: CGSize, minimum: Double = 16) -> CropRect {
        let effectiveMinWidth = min(minimum, Double(size.width))
        let effectiveMinHeight = min(minimum, Double(size.height))
        let maxWidth = Double(size.width)
        let maxHeight = Double(size.height)
        let newWidth = min(max(width, effectiveMinWidth), maxWidth)
        let newHeight = min(max(height, effectiveMinHeight), maxHeight)
        let newX = min(max(x, 0), max(0, Double(size.width) - newWidth))
        let newY = min(max(y, 0), max(0, Double(size.height) - newHeight))
        return CropRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    mutating func setOriginX(_ value: Double, in imageSize: CGSize, minimum: Double = 16) {
        let maxX = max(0, Double(imageSize.width) - minimum)
        x = min(max(value, 0), maxX)
        if x + width > Double(imageSize.width) {
            width = max(minimum, Double(imageSize.width) - x)
        }
        self = clamped(to: imageSize, minimum: minimum)
    }

    mutating func setOriginY(_ value: Double, in imageSize: CGSize, minimum: Double = 16) {
        let maxY = max(0, Double(imageSize.height) - minimum)
        y = min(max(value, 0), maxY)
        if y + height > Double(imageSize.height) {
            height = max(minimum, Double(imageSize.height) - y)
        }
        self = clamped(to: imageSize, minimum: minimum)
    }

    mutating func setWidth(_ value: Double, in imageSize: CGSize, minimum: Double = 16) {
        let maxWidth = Double(imageSize.width) - x
        width = min(max(value, minimum), maxWidth)
        self = clamped(to: imageSize, minimum: minimum)
    }

    mutating func setHeight(_ value: Double, in imageSize: CGSize, minimum: Double = 16) {
        let maxHeight = Double(imageSize.height) - y
        height = min(max(value, minimum), maxHeight)
        self = clamped(to: imageSize, minimum: minimum)
    }
}

struct ConversionSettings: Codable, Equatable {
    var outputFormat: OutputFormat = .webp
    var quality: Int = 82
    var resizeMode: ResizeMode = .fit
    var targetWidth: Int = 300
    var targetHeight: Int = 300
    var previewBackground: PreviewBackground = .gray
    var pdfAutoTrimWhitespace: Bool = false
    var paddingEnabled: Bool = false
    var paddingPixels: Int = 0
    var paddingColor: ColorHex = .white
    var canvasColor: ColorHex = .white
    var saveLocation: SaveLocation = .original
    var chosenFolderPath: String = ""
    var prefix: String = ""
    var suffix: String = ""
    var conflictAction: NameConflictAction = .rename

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputFormat = try container.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .webp
        quality = try container.decodeIfPresent(Int.self, forKey: .quality) ?? 82
        resizeMode = try container.decodeIfPresent(ResizeMode.self, forKey: .resizeMode) ?? .fit
        targetWidth = try container.decodeIfPresent(Int.self, forKey: .targetWidth) ?? 300
        targetHeight = try container.decodeIfPresent(Int.self, forKey: .targetHeight) ?? 300
        previewBackground = try container.decodeIfPresent(PreviewBackground.self, forKey: .previewBackground) ?? .gray
        pdfAutoTrimWhitespace = try container.decodeIfPresent(Bool.self, forKey: .pdfAutoTrimWhitespace) ?? false
        paddingEnabled = try container.decodeIfPresent(Bool.self, forKey: .paddingEnabled) ?? false
        paddingPixels = try container.decodeIfPresent(Int.self, forKey: .paddingPixels) ?? 0
        paddingColor = try container.decodeIfPresent(ColorHex.self, forKey: .paddingColor) ?? .white
        canvasColor = try container.decodeIfPresent(ColorHex.self, forKey: .canvasColor) ?? .white
        saveLocation = try container.decodeIfPresent(SaveLocation.self, forKey: .saveLocation) ?? .original
        chosenFolderPath = try container.decodeIfPresent(String.self, forKey: .chosenFolderPath) ?? ""
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        suffix = try container.decodeIfPresent(String.self, forKey: .suffix) ?? ""
        conflictAction = try container.decodeIfPresent(NameConflictAction.self, forKey: .conflictAction) ?? .rename
    }
}

enum SelectionMode {
    case none
    case single(ImageJob)
    case multiple([ImageJob])
}

enum JobStatus: Equatable {
    case pending
    case processing
    case succeeded(URL)
    case failed(String)

    var label: String {
        switch self {
        case .pending: "待機中"
        case .processing: "処理中"
        case .succeeded: "完了"
        case .failed: "失敗"
        }
    }
}

@MainActor
final class ImageJob: ObservableObject, Identifiable {
    let id = UUID()
    let inputURL: URL
    let source: ImageSource
    let pageCount: Int
    @Published var pageIndex: Int
    @Published var pixelSize: CGSize
    @Published var cropRect: CropRect
    @Published var status: JobStatus = .pending

    var displayName: String {
        guard pageCount > 1 else { return inputURL.lastPathComponent }
        return "\(inputURL.lastPathComponent) p.\(pageIndex + 1)"
    }

    var pageLabel: String? {
        guard pageCount > 1 else { return nil }
        return "\(pageIndex + 1)/\(pageCount) ページ"
    }

    init(inputURL: URL, source: ImageSource, pixelSize: CGSize, pageIndex: Int = 0, pageCount: Int = 1) {
        self.inputURL = inputURL
        self.source = source
        self.pageIndex = pageIndex
        self.pageCount = pageCount
        self.pixelSize = pixelSize
        self.cropRect = .full(size: pixelSize)
    }
}
