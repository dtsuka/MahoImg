import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject private var state: AppState

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

            Section("リサイズ") {
                Picker("モード", selection: $state.settings.resizeMode) {
                    ForEach(ResizeMode.allCases) { mode in
                        Text(mode.rawValue)
                            .tag(mode)
                            .help(mode.helpText)
                    }
                }
                .help(state.settings.resizeMode.helpText)

                Text(state.settings.resizeMode.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PixelInputRow(label: "幅", value: $state.settings.targetWidth)
                PixelInputRow(label: "高さ", value: $state.settings.targetHeight)
            }

            Section("トリミング") {
                if let job = state.selectedJob {
                    CropControls(job: job)
                } else {
                    Text("画像を選択してください")
                        .foregroundStyle(.secondary)
                }
            }

            Section("余白") {
                Toggle("余白を追加", isOn: $state.settings.paddingEnabled)
                PixelInputRow(label: "幅", value: $state.settings.paddingPixels)
                ColorPicker("色", selection: paddingColorBinding, supportsOpacity: false)
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
                Text(state.settings.chosenFolderPath.isEmpty ? "未選択" : state.settings.chosenFolderPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
        Binding(
            get: { Int(job.cropRect.x.rounded()) },
            set: { newValue in
                var rect = job.cropRect
                let maxX = max(0, Double(job.pixelSize.width) - 16)
                rect.x = min(max(Double(newValue), 0), maxX)
                if rect.x + rect.width > Double(job.pixelSize.width) {
                    rect.width = max(16, Double(job.pixelSize.width) - rect.x)
                }
                job.cropRect = rect.clamped(to: job.pixelSize)
            }
        )
    }

    private var cropYBinding: Binding<Int> {
        Binding(
            get: { Int(job.cropRect.y.rounded()) },
            set: { newValue in
                var rect = job.cropRect
                let maxY = max(0, Double(job.pixelSize.height) - 16)
                rect.y = min(max(Double(newValue), 0), maxY)
                if rect.y + rect.height > Double(job.pixelSize.height) {
                    rect.height = max(16, Double(job.pixelSize.height) - rect.y)
                }
                job.cropRect = rect.clamped(to: job.pixelSize)
            }
        )
    }

    private var cropWidthBinding: Binding<Int> {
        Binding(
            get: { Int(job.cropRect.width.rounded()) },
            set: { newValue in
                var rect = job.cropRect
                let maxWidth = Double(job.pixelSize.width) - rect.x
                rect.width = min(max(Double(newValue), 16), maxWidth)
                job.cropRect = rect.clamped(to: job.pixelSize)
            }
        )
    }

    private var cropHeightBinding: Binding<Int> {
        Binding(
            get: { Int(job.cropRect.height.rounded()) },
            set: { newValue in
                var rect = job.cropRect
                let maxHeight = Double(job.pixelSize.height) - rect.y
                rect.height = min(max(Double(newValue), 16), maxHeight)
                job.cropRect = rect.clamped(to: job.pixelSize)
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
