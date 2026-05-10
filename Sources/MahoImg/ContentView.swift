import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
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
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let data = item as? Data
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                if let url {
                    Task { @MainActor in
                        state.addURLs([url])
                    }
                }
            }
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
                .disabled(state.selectedJobID == nil)
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

            List(selection: $state.selectedJobID) {
                ForEach(state.jobs) { job in
                    JobRow(job: job)
                        .tag(job.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ImageProcessor.selectableContentTypes
        panel.prompt = "追加"
        if panel.runModal() == .OK {
            state.addURLs(panel.urls)
        }
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
                Text(job.inputURL.lastPathComponent)
                    .lineLimit(1)
                Text("\(Int(job.pixelSize.width)) x \(Int(job.pixelSize.height)) ・ \(job.status.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
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
}

struct BottomBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Text(state.progressText)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                state.processAll()
            } label: {
                Label("変換実行", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.jobs.isEmpty || state.isProcessing)
        }
    }
}

#Preview("MahoImg") {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 980, height: 680)
}
