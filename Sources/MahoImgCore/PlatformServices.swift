import AppKit

enum MultiPagePDFChoice {
    case singleItem
    case allPages
    case cancel
}

enum PlatformServices {
    @MainActor
    static func chooseOutputFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    @MainActor
    static func openFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ImageProcessor.selectableContentTypes
        panel.prompt = "追加"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    @MainActor
    static func multiPagePDFChoice(for url: URL, pageCount: Int) -> MultiPagePDFChoice {
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

    @MainActor
    static func showMissingMagickAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ImageMagick が見つかりません"
        alert.informativeText = ImageProcessor.magickInstallGuide
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
