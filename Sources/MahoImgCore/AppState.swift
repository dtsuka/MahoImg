import Foundation
import PDFKit

@MainActor
public final class AppState: ObservableObject {
    @Published var jobs: [ImageJob] = []
    @Published var selectedJobIDs: Set<UUID> = []
    @Published var settings: ConversionSettings = SettingsStore.load() {
        didSet { SettingsStore.save(settings) }
    }
    @Published var isProcessing = false
    @Published var progressText = "待機中"
    private var didShowMissingMagickGuide = false
    private var processingTask: Task<Void, Never>?

    public init() {}

    var selectedJob: ImageJob? {
        selectedJobs.first
    }

    var selectedJobs: [ImageJob] {
        jobs.filter { selectedJobIDs.contains($0.id) }
    }

    var hasSelection: Bool {
        !selectedJobIDs.isEmpty
    }

    public func addURLs(_ urls: [URL], activateAdded: Bool = false) {
        let newJobs = urls.flatMap { resolvedJobs(from: $0) }
        var jobsToActivate: [ImageJob] = []

        for job in newJobs {
            if let existingJob = jobs.first(where: { $0.inputURL == job.inputURL && $0.pageIndex == job.pageIndex }) {
                jobsToActivate.append(existingJob)
                continue
            }

            jobs.append(job)
            jobsToActivate.append(job)
        }

        if activateAdded, !jobsToActivate.isEmpty {
            selectedJobIDs = Set(jobsToActivate.map(\.id))
            return
        }

        if selectedJobIDs.isEmpty, let firstJobID = jobs.first?.id {
            selectedJobIDs = [firstJobID]
        }
    }

    func removeSelected() {
        guard !selectedJobIDs.isEmpty else { return }
        jobs.removeAll { selectedJobIDs.contains($0.id) }
        selectedJobIDs = jobs.first.map { [$0.id] } ?? []
    }

    func removeAllJobs() {
        guard !isProcessing else { return }
        jobs.removeAll()
        selectedJobIDs = []
        progressText = "待機中"
    }

    func resetCropForSelected() {
        guard let selectedJob else { return }
        selectedJob.cropRect = .full(size: selectedJob.pixelSize)
    }

    func setPage(_ pageIndex: Int, for job: ImageJob) {
        let clampedIndex = min(max(pageIndex, 0), job.pageCount - 1)
        guard clampedIndex != job.pageIndex else { return }
        guard let size = ImageMetadataReader.pixelSize(for: job.inputURL, pageIndex: clampedIndex) else { return }
        job.pageIndex = clampedIndex
        job.pixelSize = size
        job.cropRect = .full(size: size)
        job.status = .pending
    }

    func chooseOutputFolder() {
        guard let path = PlatformServices.chooseOutputFolder() else { return }
        settings.chosenFolderPath = path
        settings.saveLocation = .chosenFolder
    }

    func processAll() {
        process(jobs, completionText: "完了")
    }

    func processSelected() {
        process(selectedJobs, completionText: "選択項目の変換完了")
    }

    func cancelProcessing() {
        processingTask?.cancel()
    }

    func showMissingMagickGuideIfNeeded() {
        guard !didShowMissingMagickGuide else { return }
        guard !ImageProcessor.isMagickAvailable() else { return }
        didShowMissingMagickGuide = true
        PlatformServices.showMissingMagickAlert()
    }

    private func process(_ targetJobs: [ImageJob], completionText: String) {
        guard !isProcessing else { return }
        guard !targetJobs.isEmpty else { return }

        processingTask?.cancel()
        isProcessing = true
        progressText = "開始中"
        let settingsSnapshot = settings

        processingTask = Task {
            var completed = 0
            defer {
                for job in targetJobs where job.status == .processing {
                    job.status = .pending
                }
                isProcessing = false
                processingTask = nil
            }

            for job in targetJobs {
                guard !Task.isCancelled else {
                    progressText = "キャンセルしました"
                    return
                }

                job.status = .processing
                do {
                    let outputURL = try ImageProcessor.outputURL(
                        for: job.inputURL,
                        settings: settingsSnapshot,
                        pageIndex: job.pageIndex,
                        pageCount: job.pageCount
                    )
                    try await ImageProcessor.run(
                        inputURL: job.inputURL,
                        outputURL: outputURL,
                        settings: settingsSnapshot,
                        cropRect: job.cropRect,
                        imageSize: job.pixelSize,
                        pageIndex: job.pageIndex
                    )
                    guard !Task.isCancelled else {
                        progressText = "キャンセルしました"
                        return
                    }
                    job.status = .succeeded(outputURL)
                } catch {
                    job.status = .failed(error.localizedDescription)
                }
                completed += 1
                progressText = "\(completed)/\(targetJobs.count) 完了"
            }

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
                guard let fileURL = item as? URL, ImageSource.classify(fileURL) != nil else { continue }
                resolved.append(contentsOf: resolvedJobs(from: fileURL))
            }
            return resolved.sorted {
                if $0.inputURL == $1.inputURL {
                    return $0.pageIndex < $1.pageIndex
                }
                return $0.inputURL.path < $1.inputURL.path
            }
        }
        guard ImageSource.classify(url) != nil else { return [] }
        return jobs(for: url)
    }

    private func jobs(for url: URL) -> [ImageJob] {
        if case .pdf = ImageSource.classify(url) {
            return pdfJobs(for: url)
        }

        guard let size = ImageMetadataReader.pixelSize(for: url) else { return [] }
        return [ImageJob(inputURL: url, pixelSize: size)]
    }

    private func pdfJobs(for url: URL) -> [ImageJob] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return [] }
        let pageCount = document.pageCount
        if pageCount == 1 {
            guard let size = ImageMetadataReader.pdfPageSize(for: url, pageIndex: 0) else { return [] }
            return [ImageJob(inputURL: url, pixelSize: size, pageCount: pageCount)]
        }

        switch PlatformServices.multiPagePDFChoice(for: url, pageCount: pageCount) {
        case .singleItem:
            guard let size = ImageMetadataReader.pdfPageSize(for: url, pageIndex: 0) else { return [] }
            return [ImageJob(inputURL: url, pixelSize: size, pageCount: pageCount)]
        case .allPages:
            return (0..<pageCount).compactMap { pageIndex in
                guard let size = ImageMetadataReader.pdfPageSize(for: url, pageIndex: pageIndex) else { return nil }
                return ImageJob(inputURL: url, pixelSize: size, pageIndex: pageIndex, pageCount: pageCount)
            }
        case .cancel:
            return []
        }
    }
}
