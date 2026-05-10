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
    case fillCrop = "塗り足しクロップ"
    case width = "幅指定"
    case height = "高さ指定"
    case exact = "幅高さ指定"

    var id: String { rawValue }

    var helpText: String {
        switch self {
        case .none:
            "元画像のピクセルサイズを維持します。"
        case .fit:
            "指定した幅と高さの内側に、縦横比を維持して画像全体を収めます。"
        case .fillCrop:
            "指定サイズを埋めるまで拡大縮小し、はみ出した部分を中央で切り落とします。"
        case .width:
            "幅を指定値に合わせ、高さは縦横比から自動計算します。"
        case .height:
            "高さを指定値に合わせ、幅は縦横比から自動計算します。"
        case .exact:
            "指定した幅と高さに強制変形します。縦横比が変わる場合があります。"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "フィット" {
            self = .fit
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
        let maxWidth = max(minimum, Double(size.width))
        let maxHeight = max(minimum, Double(size.height))
        let newWidth = min(max(width, minimum), maxWidth)
        let newHeight = min(max(height, minimum), maxHeight)
        let newX = min(max(x, 0), max(0, Double(size.width) - newWidth))
        let newY = min(max(y, 0), max(0, Double(size.height) - newHeight))
        return CropRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }
}

struct ConversionSettings: Codable, Equatable {
    var outputFormat: OutputFormat = .webp
    var quality: Int = 82
    var resizeMode: ResizeMode = .fit
    var targetWidth: Int = 300
    var targetHeight: Int = 300
    var paddingEnabled: Bool = false
    var paddingPixels: Int = 0
    var paddingColor: ColorHex = .white
    var saveLocation: SaveLocation = .original
    var chosenFolderPath: String = ""
    var prefix: String = ""
    var suffix: String = ""
    var conflictAction: NameConflictAction = .rename
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
    let pixelSize: CGSize
    @Published var cropRect: CropRect
    @Published var status: JobStatus = .pending

    init(inputURL: URL, pixelSize: CGSize) {
        self.inputURL = inputURL
        self.pixelSize = pixelSize
        self.cropRect = .full(size: pixelSize)
    }
}
