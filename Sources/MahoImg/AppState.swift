import AppKit
import Foundation
import ImageIO

@MainActor
final class AppState: ObservableObject {
    @Published var jobs: [ImageJob] = []
    @Published var selectedJobID: UUID?
    @Published var settings: ConversionSettings = SettingsStore.load() {
        didSet { SettingsStore.save(settings) }
    }
    @Published var isProcessing = false
    @Published var progressText = "待機中"

    var selectedJob: ImageJob? {
        jobs.first { $0.id == selectedJobID }
    }

    func addURLs(_ urls: [URL]) {
        let imageURLs = urls.flatMap { resolvedImageURLs(from: $0) }
        for url in imageURLs where !jobs.contains(where: { $0.inputURL == url }) {
            guard let size = Self.pixelSize(for: url) else { continue }
            jobs.append(ImageJob(inputURL: url, pixelSize: size))
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
        guard !isProcessing else { return }
        isProcessing = true
        progressText = "開始中"

        Task {
            var completed = 0
            for job in jobs {
                job.status = .processing
                do {
                    let outputURL = try ImageProcessor.outputURL(for: job.inputURL, settings: settings)
                    try await ImageProcessor.run(inputURL: job.inputURL, outputURL: outputURL, settings: settings, cropRect: job.cropRect)
                    job.status = .succeeded(outputURL)
                } catch {
                    job.status = .failed(error.localizedDescription)
                }
                completed += 1
                progressText = "\(completed)/\(jobs.count) 完了"
            }
            isProcessing = false
            progressText = "完了"
        }
    }

    private func resolvedImageURLs(from url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if isDirectory.boolValue {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else {
                return []
            }
            return enumerator.compactMap { item in
                guard let fileURL = item as? URL, ImageProcessor.isSupportedImage(fileURL) else { return nil }
                return fileURL
            }.sorted { $0.path < $1.path }
        }
        return ImageProcessor.isSupportedImage(url) ? [url] : []
    }

    private static func pixelSize(for url: URL) -> CGSize? {
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
