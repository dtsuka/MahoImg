import AppKit
import MahoImgCore
import SwiftUI

@main
struct MahoImgApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("MahoImg", id: "main") {
            ContentView()
                .environmentObject(state)
                .onAppear {
                    appDelegate.openURLsHandler = { [state] urls in
                        state.addURLs(urls, activateAdded: true)
                    }

                    let pendingURLs = appDelegate.consumePendingURLs()
                    if !pendingURLs.isEmpty {
                        state.addURLs(pendingURLs, activateAdded: true)
                    }
                }
                .frame(minWidth: 980, minHeight: 680)
                .background(WindowTitleBarConfigurator())
        }
        .windowStyle(.titleBar)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    var openURLsHandler: (([URL]) -> Void)?
    private var pendingURLs: [URL] = []
    private var openURLsFlushTask: Task<Void, Never>?

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        scheduleOpenURLsFlush(application: application)
    }

    func consumePendingURLs() -> [URL] {
        defer { pendingURLs.removeAll() }
        return pendingURLs
    }

    private func scheduleOpenURLsFlush(application: NSApplication) {
        openURLsFlushTask?.cancel()
        openURLsFlushTask = Task { @MainActor [weak self, weak application] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.flushPendingOpenURLs()
            if let application {
                self.showMainWindow(application: application)
            }
        }
    }

    private func flushPendingOpenURLs() {
        guard let openURLsHandler else { return }
        let urls = consumePendingURLs()
        guard !urls.isEmpty else { return }
        openURLsHandler(urls)
    }

    private func showMainWindow(application: NSApplication) {
        application.activate(ignoringOtherApps: true)
        application.windows.first?.makeKeyAndOrderFront(nil)
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
