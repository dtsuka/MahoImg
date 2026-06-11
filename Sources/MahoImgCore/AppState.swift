import Foundation
import PDFKit

@MainActor
public final class AppState: ObservableObject {
    @Published var jobs: [ImageJob] = []
    @Published var selectedJobIDs: Set<UUID> = []
    @Published var settings: ConversionSettings {
        didSet { settingsStorage.save(settings) }
    }
    @Published var isProcessing = false
    @Published var progressText = "待機中"
    private let settingsStorage: SettingsStorage
    private var didShowMissingMagickGuide = false
    private var processingTask: Task<Void, Never>?
    private var runningProcess: Process?

    public convenience init() {
        self.init(settingsStorage: SettingsStorage(
            load: SettingsStore.load,
            save: SettingsStore.save
        ))
    }

    init(settingsStorage: SettingsStorage) {
        self.settingsStorage = settingsStorage
        settings = settingsStorage.load()
    }

    var selectedJob: ImageJob? {
        if case .single(let job) = selectionMode {
            return job
        }
        return nil
    }

    var selectedJobs: [ImageJob] {
        jobs.filter { selectedJobIDs.contains($0.id) }
    }

    var hasSelection: Bool {
        !selectedJobIDs.isEmpty
    }

    public var canProcessAll: Bool {
        !jobs.isEmpty && !isProcessing
    }

    public var canProcessSelected: Bool {
        hasSelection && !isProcessing
    }

    var selectionMode: SelectionMode {
        let selected = selectedJobs
        switch selected.count {
        case 0:
            return .none
        case 1:
            return .single(selected[0])
        default:
            return .multiple(selected)
        }
    }

    @discardableResult
    public func addURLs(_ urls: [URL]) -> Set<UUID> {
        let newJobs = urls.flatMap { resolvedJobs(from: $0) }
        var addedJobs: [ImageJob] = []

        for job in newJobs {
            if let existingJob = jobs.first(where: { $0.inputURL == job.inputURL && $0.pageIndex == job.pageIndex }) {
                addedJobs.append(existingJob)
                continue
            }

            jobs.append(job)
            addedJobs.append(job)
        }

        if selectedJobIDs.isEmpty, let firstJobID = jobs.first?.id {
            selectedJobIDs = [firstJobID]
        }

        return Set(addedJobs.map(\.id))
    }

    public func selectJobIDs(_ ids: Set<UUID>) {
        selectedJobIDs = ids
    }

    func selectJobs(_ jobs: [ImageJob]) {
        selectJobIDs(Set(jobs.map(\.id)))
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
        PreviewImageCache.clear()
    }

    func resetCropForSelected() {
        guard case .single(let job) = selectionMode else { return }
        job.cropRect = .full(size: job.pixelSize)
    }

    func setPage(_ pageIndex: Int, for job: ImageJob) {
        let clampedIndex = min(max(pageIndex, 0), job.pageCount - 1)
        guard clampedIndex != job.pageIndex else { return }
        guard let size = ImageMetadataReader.pixelSize(for: job.source, pageIndex: clampedIndex) else { return }
        job.pageIndex = clampedIndex
        job.pixelSize = size
        job.cropRect = .full(size: size)
        job.status = .pending
    }

    func chooseOutputFolder() {
        guard let path = PlatformServices.chooseOutputFolder() else { return }
        setOutputFolder(URL(fileURLWithPath: path, isDirectory: true))
    }

    @discardableResult
    func setOutputFolder(_ url: URL) -> Bool {
        guard let folder = OutputFolder.existingDirectory(at: url) else { return false }
        settings.chosenFolderPath = folder.path
        settings.saveLocation = .chosenFolder
        return true
    }

    public func processAll() {
        process(jobs, completionText: "完了")
    }

    public func processSelected() {
        process(selectedJobs, completionText: "選択項目の変換完了")
    }

    func cancelProcessing() {
        processingTask?.cancel()
        runningProcess?.terminate()
        runningProcess = nil
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
        runningProcess?.terminate()
        runningProcess = nil
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
                runningProcess = nil
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
                        source: job.source,
                        pageIndex: job.pageIndex,
                        onProcessStarted: { [weak self] process in
                            self?.runningProcess = process
                        }
                    )
                    guard !Task.isCancelled else {
                        progressText = "キャンセルしました"
                        return
                    }
                    job.status = .succeeded(outputURL)
                } catch {
                    if Task.isCancelled {
                        progressText = "キャンセルしました"
                        return
                    }
                    job.status = .failed(error.localizedDescription)
                }
                completed += 1
                progressText = "\(completed)/\(targetJobs.count) 完了"
            }

            progressText = completionText
        }
    }

    private func resolvedJobs(from url: URL) -> [ImageJob] {
        if let directory = OutputFolder.existingDirectory(at: url) {
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
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
        guard let source = ImageSource.classify(url) else { return [] }
        return jobs(for: url, source: source)
    }

    private func jobs(for url: URL, source: ImageSource) -> [ImageJob] {
        if case .pdf = source {
            return pdfJobs(for: url, source: source)
        }

        guard let size = ImageMetadataReader.pixelSize(for: source) else { return [] }
        return [ImageJob(inputURL: url, source: source, pixelSize: size)]
    }

    private func pdfJobs(for url: URL, source: ImageSource) -> [ImageJob] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return [] }
        let pageCount = document.pageCount
        if pageCount == 1 {
            guard let size = ImageMetadataReader.pdfPageSize(for: url, pageIndex: 0) else { return [] }
            return [ImageJob(inputURL: url, source: source, pixelSize: size, pageCount: pageCount)]
        }

        switch PlatformServices.multiPagePDFChoice(for: url, pageCount: pageCount) {
        case .singleItem:
            guard let size = ImageMetadataReader.pdfPageSize(for: url, pageIndex: 0) else { return [] }
            return [ImageJob(inputURL: url, source: source, pixelSize: size, pageCount: pageCount)]
        case .allPages:
            return (0..<pageCount).compactMap { pageIndex in
                guard let size = ImageMetadataReader.pdfPageSize(for: url, pageIndex: pageIndex) else { return nil }
                return ImageJob(inputURL: url, source: source, pixelSize: size, pageIndex: pageIndex, pageCount: pageCount)
            }
        case .cancel:
            return []
        }
    }
}
