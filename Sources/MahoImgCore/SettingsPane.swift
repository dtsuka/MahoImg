import SwiftUI
import UniformTypeIdentifiers

struct SettingsPane: View {
    @EnvironmentObject private var state: AppState
    @State private var isOutputFolderDropTargeted = false

    var body: some View {
        Form {
            Section("出力") {
                Picker("形式", selection: $state.settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if state.settings.outputFormat != .png {
                    HStack {
                        Text("品質")
                        Slider(value: qualityBinding, in: 1...100)
                        TextField("品質", value: qualityInputBinding, format: .number)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .frame(width: 56)
                    }
                }
            }

            Section("保存先") {
                Picker("場所", selection: $state.settings.saveLocation) {
                    ForEach(SaveLocation.allCases) { location in
                        Text(location.rawValue).tag(location)
                    }
                }
                Button {
                    state.chooseOutputFolder()
                } label: {
                    Label("保存先を選択", systemImage: "folder")
                }
                outputFolderPathLabel
                    .onDrop(of: [.folder], isTargeted: $isOutputFolderDropTargeted, perform: handleOutputFolderDrop(providers:))
            }

            Section("リサイズ") {
                Picker("出力方法", selection: $state.settings.resizeMode) {
                    ForEach(ResizeMode.allCases) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                            .help(mode.helpText)
                    }
                }
                .help(state.settings.resizeMode.helpText)

                Text(state.settings.resizeMode.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let label = state.settings.resizeMode.widthLabel {
                    PixelInputRow(label: label, value: $state.settings.targetWidth)
                }
                if let label = state.settings.resizeMode.heightLabel {
                    PixelInputRow(label: label, value: $state.settings.targetHeight)
                }

                if state.settings.resizeMode == .canvasFit {
                    ColorPicker("キャンバス背景", selection: canvasColorBinding, supportsOpacity: false)
                    Label(
                        "出力は常に \(safeTargetWidth) × \(safeTargetHeight) px になります。",
                        systemImage: "rectangle.inset.filled"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("PDF") {
                Toggle("白余白を自動トリム", isOn: $state.settings.pdfAutoTrimWhitespace)
                Text("オフの場合はPreview.appと同じくPDFページ全体を変換します。オンにすると、ページ周囲の白い余白を落として内容を大きく出力します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("トリミング") {
                switch state.selectionMode {
                case .single(let job):
                    CropControls(job: job)
                case .multiple(let jobs):
                    Text("\(jobs.count)件選択中です。トリミングは1件選択時のみ編集できます。")
                        .foregroundStyle(.secondary)
                case .none:
                    Text("画像を選択してください")
                        .foregroundStyle(.secondary)
                }
            }

            Section("外側の余白") {
                Toggle("出力画像の外側に余白を追加", isOn: $state.settings.paddingEnabled)
                if state.settings.paddingEnabled {
                    PixelInputRow(label: "幅", value: $state.settings.paddingPixels)
                    ColorPicker("余白の色", selection: paddingColorBinding, supportsOpacity: false)
                }
            }

            Section("ファイル名") {
                TextField("接頭辞", text: $state.settings.prefix)
                    .textFieldStyle(.roundedBorder)
                TextField("接尾辞", text: $state.settings.suffix)
                    .textFieldStyle(.roundedBorder)
                Picker("同名時", selection: $state.settings.conflictAction) {
                    ForEach(NameConflictAction.allCases) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var outputFolderPathLabel: some View {
        Button {
            guard let outputFolderURL else { return }
            PlatformServices.openInFinder(outputFolderURL)
        } label: {
            Text(state.settings.chosenFolderPath.isEmpty ? "未選択" : state.settings.chosenFolderPath)
                .font(.caption)
                .foregroundStyle(outputFolderURL == nil ? .secondary : .primary)
                .lineLimit(2)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isOutputFolderDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isOutputFolderDropTargeted ? Color.accentColor : Color.clear,
                            style: StrokeStyle(lineWidth: 1, dash: [4])
                        )
                }
        }
        .buttonStyle(.plain)
        .onDrop(of: [.folder], isTargeted: $isOutputFolderDropTargeted, perform: handleOutputFolderDrop(providers:))
        .help(outputFolderURL == nil ? "保存先フォルダをドロップ" : "クリックしてFinderで保存先を開く。保存先フォルダをドロップ")
    }

    private var outputFolderURL: URL? {
        OutputFolder.existingDirectory(from: state.settings.chosenFolderPath)
    }

    private func handleOutputFolderDrop(providers: [NSItemProvider]) -> Bool {
        guard FileDropHandler.accepts(providers: providers, typeIdentifiers: FileDropHandler.folderDropTypeIdentifiers) else {
            return false
        }
        Task { @MainActor in
            let urls = await FileDropHandler.loadURLs(
                from: providers,
                typeIdentifiers: FileDropHandler.folderDropTypeIdentifiers
            )
            _ = urls.first(where: state.setOutputFolder)
        }
        return true
    }

    private var qualityBinding: Binding<Double> {
        Binding(
            get: { Double(state.settings.quality) },
            set: { state.settings.quality = clampedQuality(Int($0.rounded())) }
        )
    }

    private var qualityInputBinding: Binding<Int> {
        Binding(
            get: { state.settings.quality },
            set: { state.settings.quality = clampedQuality($0) }
        )
    }

    private func clampedQuality(_ value: Int) -> Int {
        min(max(value, 1), 100)
    }

    private var paddingColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: state.settings.paddingColor.nsColor) },
            set: { newColor in
                state.settings.paddingColor = ColorHex(value: newColor.hexString)
            }
        )
    }

    private var canvasColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: state.settings.canvasColor.nsColor) },
            set: { newColor in
                state.settings.canvasColor = ColorHex(value: newColor.hexString)
            }
        )
    }

    private var safeTargetWidth: Int {
        max(state.settings.targetWidth, 1)
    }

    private var safeTargetHeight: Int {
        max(state.settings.targetHeight, 1)
    }
}

private struct CropControls: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var job: ImageJob
    private let labelWidth = 44.0

    var body: some View {
        if job.pageCount > 1 {
            HStack {
                Text("ページ")
                    .lineLimit(1)
                    .frame(width: labelWidth, alignment: .leading)
                TextField("ページ", value: pageBinding, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 64)
                Stepper("ページ", value: pageBinding, in: 1...job.pageCount)
                    .labelsHidden()
                Text("/ \(job.pageCount)")
                    .foregroundStyle(.secondary)
            }
        }

        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("X")
                    .frame(width: labelWidth, alignment: .leading)
                TextField("X", value: cropXBinding, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                Text("Y")
                    .frame(width: labelWidth, alignment: .leading)
                TextField("Y", value: cropYBinding, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
            }
            GridRow {
                Text("幅")
                    .frame(width: labelWidth, alignment: .leading)
                TextField("幅", value: cropWidthBinding, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                Text("高さ")
                    .frame(width: labelWidth, alignment: .leading)
                TextField("高さ", value: cropHeightBinding, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
            }
        }
        Button {
            state.resetCropForSelected()
        } label: {
            Label("全体に戻す", systemImage: "arrow.counterclockwise")
        }
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { job.pageIndex + 1 },
            set: { state.setPage($0 - 1, for: job) }
        )
    }

    private var cropXBinding: Binding<Int> {
        cropBinding(get: \.x) { rect, value in
            rect.setOriginX(Double(value), in: job.pixelSize)
        }
    }

    private var cropYBinding: Binding<Int> {
        cropBinding(get: \.y) { rect, value in
            rect.setOriginY(Double(value), in: job.pixelSize)
        }
    }

    private var cropWidthBinding: Binding<Int> {
        cropBinding(get: \.width) { rect, value in
            rect.setWidth(Double(value), in: job.pixelSize)
        }
    }

    private var cropHeightBinding: Binding<Int> {
        cropBinding(get: \.height) { rect, value in
            rect.setHeight(Double(value), in: job.pixelSize)
        }
    }

    private func cropBinding(
        get keyPath: KeyPath<CropRect, Double>,
        apply: @escaping (inout CropRect, Int) -> Void
    ) -> Binding<Int> {
        Binding(
            get: { Int(job.cropRect[keyPath: keyPath].rounded()) },
            set: { newValue in
                var rect = job.cropRect
                apply(&rect, newValue)
                job.cropRect = rect
            }
        )
    }
}

private struct PixelInputRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 44, alignment: .leading)
            TextField(label, value: $value, format: .number)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
            Text("px")
        }
    }
}

private extension Color {
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02x%02x%02x", red, green, blue)
    }
}
