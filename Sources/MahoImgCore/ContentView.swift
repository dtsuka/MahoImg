import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @EnvironmentObject private var state: AppState

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            JobListView()
                .frame(width: 260)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(spacing: 0) {
                PreviewPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                BottomBar()
                    .padding(12)
                    .background(Color(nsColor: .windowBackgroundColor))
            }

            Divider()

            SettingsPane()
                .frame(width: 330)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop(providers:))
        .onAppear {
            state.showMissingMagickGuideIfNeeded()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard FileDropHandler.accepts(providers: providers) else { return false }
        Task { @MainActor in
            let urls = await FileDropHandler.loadURLs(from: providers)
            guard !urls.isEmpty else { return }
            state.addURLs(urls)
        }
        return true
    }
}

struct JobListView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("画像")
                    .font(.headline)
                Spacer()
                Button {
                    openFiles()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 16, height: 16)
                }
                .controlSize(.regular)
                .frame(width: 28, height: 28)
                .help("画像またはフォルダを追加")

                Button {
                    state.removeSelected()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 16, height: 16)
                }
                .controlSize(.regular)
                .frame(width: 28, height: 28)
                .disabled(!state.hasSelection)
                .help("選択画像を削除")

                Button {
                    state.removeAllJobs()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 16, height: 16)
                }
                .controlSize(.regular)
                .frame(width: 28, height: 28)
                .disabled(state.jobs.isEmpty || state.isProcessing)
                .help("画像リストを空にする")
            }
            .padding(12)

            List(selection: $state.selectedJobIDs) {
                ForEach(state.jobs) { job in
                    JobRow(job: job)
                        .tag(job.id)
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                state.processAll()
            } label: {
                Label("一括変換", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.jobs.isEmpty || state.isProcessing)
            .padding(12)
        }
    }

    private func openFiles() {
        state.addURLs(PlatformServices.openFiles())
    }
}

struct JobRow: View {
    @ObservedObject var job: ImageJob

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
        .help(helpText)
    }

    private var iconName: String {
        switch job.status {
        case .pending: "photo"
        case .processing: "hourglass"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch job.status {
        case .pending: .secondary
        case .processing: .blue
        case .succeeded: .green
        case .failed: .red
        }
    }

    private var detailText: String {
        let size = "\(Int(job.pixelSize.width)) x \(Int(job.pixelSize.height))"
        if case .failed(let message) = job.status {
            return "\(baseDetail(size: size)) ・ 失敗: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return "\(baseDetail(size: size)) ・ \(job.status.label)"
    }

    private var detailColor: Color {
        if case .failed = job.status {
            return .red
        }
        return .secondary
    }

    private var helpText: String {
        if case .failed(let message) = job.status {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return job.displayName
    }

    private func baseDetail(size: String) -> String {
        if let pageLabel = job.pageLabel {
            return "\(size) ・ \(pageLabel)"
        }
        return size
    }
}

struct BottomBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Text(state.progressText)
                .foregroundStyle(.secondary)
            Spacer()
            if state.isProcessing {
                Button("キャンセル") {
                    state.cancelProcessing()
                }
            }
            Button {
                state.processSelected()
            } label: {
                Label(selectionButtonTitle, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!state.hasSelection || state.isProcessing)
        }
    }

    private var selectionButtonTitle: String {
        let count = state.selectedJobs.count
        if count > 1 {
            return "選択した\(count)件を変換"
        }
        return "選択項目を変換"
    }
}

#Preview("MahoImg") {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 980, height: 680)
}
