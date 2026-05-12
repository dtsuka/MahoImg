import MahoImgCore
import SwiftUI

@main
struct MahoImgApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("MahoImg") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 680)
                .background(WindowTitleBarConfigurator())
        }
        .windowStyle(.titleBar)
    }
}

private struct WindowTitleBarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = false
        window.styleMask.remove(.fullSizeContentView)
    }
}
