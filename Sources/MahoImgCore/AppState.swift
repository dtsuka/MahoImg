import AppKit
import Foundation
import ImageIO
import PDFKit

@MainActor
public final class AppState: ObservableObject {
    @Published var jobs: [ImageJob] = []
    @Published var selectedJobID: UUID?
    @Published var settings: ConversionSettings = SettingsStore.load() {
        didSet { SettingsStore.save(settings) }
    }
    @Published var isProcessing = false
    @Published var progressText = "待機中"
    private var didShowMissingMagickGuide = false

    public init() {}

    var selectedJob: ImageJob? {
        jobs.first { $0.id == selectedJobID }
    }

    public func addURLs(_ urls: [URL], activateAdded: Bool = false) {
        let newJobs = urls.flatMap { resolvedJobs(from: $0) }
        var jobToActivate: ImageJob?

        for job in newJobs {
            if let existingJob = jobs.first(where: { $0.inputURL == job.inputURL && $0.pageIndex == job.pageIndex }) {
                jobToActivate = jobToActivate ?? existingJob
                continue
            }

            jobs.append(job)
            jobToActivate = jobToActivate ?? job
        }

        if activateAdded, let jobToActivate {
            selectedJobID = jobToActivate.id
            return
        }

        if selectedJobID == nil {
            selectedJobID = jobs.first?.id
        }
    }

    func removeSelected() {
        guard let selectedJobID else { return }
        jobs.removeAll { $0.id == selectedJobID }
        self.selectedJobID = jobs.first?.id
    }

    func removeAllJobs() {
        guard !isProcessing else { return }
        jobs.removeAll()
        selectedJobID = nil
        progressText = "待機中"
    }

    func resetCropForSelected() {
        guard let selectedJob else { return }
        selectedJob.cropRect = .full(size: selectedJob.pixelSize)
    }

    func setPage(_ pageIndex: Int, for job: ImageJob) {
        let clampedIndex = min(max(pageIndex, 0), job.pageCount - 1)
        guard clampedIndex != job.pageIndex else { return }
        guard let size = Self.pixelSize(for: job.inputURL, pageIndex: clampedIndex) else { return }
        job.pageIndex = clampedIndex
        job.pixelSize = size
        job.cropRect = .full(size: size)
        job.status = .pending
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        if panel.runModal() == .OK, let url = panel.url {
            settings.chosenFolderPath = url.path
            settings.saveLocation = .chosenFolder
        }
    }

    func processAll() {
        process(jobs, completionText: "完了")
    }

    func processSelected() {
        guard let selectedJob else { return }
        process([selectedJob], completionText: "個別変換完了")
    }

    func showMissingMagickGuideIfNeeded() {
        guard !didShowMissingMagickGuide else { return }
        guard !ImageProcessor.isMagickAvailable() else { return }
        didShowMissingMagickGuide = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ImageMagick が見つかりません"
        alert.informativeText = ImageProcessor.magickInstallGuide
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func process(_ targetJobs: [ImageJob], completionText: String) {
        guard !isProcessing else { return }
        guard !targetJobs.isEmpty else { return }
        isProcessing = true
        progressText = "開始中"

        Task {
            var completed = 0
            for job in targetJobs {
                job.status = .processing
                do {
                    let outputURL = try ImageProcessor.outputURL(for: job.inputURL, settings: settings, pageIndex: job.pageIndex, pageCount: job.pageCount)
                    try await ImageProcessor.run(inputURL: job.inputURL, outputURL: outputURL, settings: settings, cropRect: job.cropRect, pageIndex: job.pageIndex)
                    job.status = .succeeded(outputURL)
                } catch {
                    job.status = .failed(error.localizedDescription)
                }
                completed += 1
                progressText = "\(completed)/\(targetJobs.count) 完了"
            }
            isProcessing = false
            progressText = completionText
        }
    }

    private func resolvedJobs(from url: URL) -> [ImageJob] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if isDirectory.boolValue {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else {
                return []
            }
            var resolved: [ImageJob] = []
            for item in enumerator {
                guard let fileURL = item as? URL, ImageProcessor.isSupportedImage(fileURL) else { continue }
                resolved.append(contentsOf: resolvedJobs(from: fileURL))
            }
            return resolved.sorted {
                if $0.inputURL == $1.inputURL {
                    return $0.pageIndex < $1.pageIndex
                }
                return $0.inputURL.path < $1.inputURL.path
            }
        }
        guard ImageProcessor.isSupportedImage(url) else { return [] }
        return jobs(for: url)
    }

    private func jobs(for url: URL) -> [ImageJob] {
        if ImageProcessor.isPDFDocument(url) {
            return pdfJobs(for: url)
        }

        guard let size = Self.pixelSize(for: url) else { return [] }
        return [ImageJob(inputURL: url, pixelSize: size)]
    }

    private func pdfJobs(for url: URL) -> [ImageJob] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return [] }
        let pageCount = document.pageCount
        if pageCount == 1 {
            guard let size = Self.pdfPageSize(for: url, pageIndex: 0) else { return [] }
            return [ImageJob(inputURL: url, pixelSize: size, pageCount: pageCount)]
        }

        switch multiPagePDFChoice(for: url, pageCount: pageCount) {
        case .singleItem:
            guard let size = Self.pdfPageSize(for: url, pageIndex: 0) else { return [] }
            return [ImageJob(inputURL: url, pixelSize: size, pageCount: pageCount)]
        case .allPages:
            return (0..<pageCount).compactMap { pageIndex in
                guard let size = Self.pdfPageSize(for: url, pageIndex: pageIndex) else { return nil }
                return ImageJob(inputURL: url, pixelSize: size, pageIndex: pageIndex, pageCount: pageCount)
            }
        case .cancel:
            return []
        }
    }

    private enum MultiPagePDFChoice {
        case singleItem
        case allPages
        case cancel
    }

    private func multiPagePDFChoice(for url: URL, pageCount: Int) -> MultiPagePDFChoice {
        let alert = NSAlert()
        alert.messageText = "このPDFには \(pageCount) ページあります。"
        alert.informativeText = "どのように追加しますか？"
        alert.addButton(withTitle: "ページを選んで追加")
        alert.addButton(withTitle: "全ページを追加")
        alert.addButton(withTitle: "キャンセル")
        alert.icon = NSWorkspace.shared.icon(forFile: url.path)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .singleItem
        case .alertSecondButtonReturn:
            return .allPages
        default:
            return .cancel
        }
    }

    private static func pixelSize(for url: URL, pageIndex: Int = 0) -> CGSize? {
        if ImageProcessor.isPDFDocument(url) {
            return pdfPageSize(for: url, pageIndex: pageIndex)
        }

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Double,
           let height = properties[kCGImagePropertyPixelHeight] as? Double {
            return CGSize(width: width, height: height)
        }

        guard let image = NSImage(contentsOf: url) else { return nil }
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    private static func pdfPageSize(for url: URL, pageIndex: Int) -> CGSize? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else {
            return nil
        }
        return page.bounds(for: .cropBox).size
    }
}

enum SettingsStore {
    private static let key = "MahoImg.ConversionSettings"

    static func load() -> ConversionSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ConversionSettings.self, from: data) else {
            return ConversionSettings()
        }
        return settings
    }

    static func save(_ settings: ConversionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
