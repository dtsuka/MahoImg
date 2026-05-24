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

    func applicationShouldHandleReopen(_ application: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        showMainWindow(application: application)
        return false
    }

    func applicationShouldOpenUntitledFile(_ application: NSApplication) -> Bool {
        pendingURLs.isEmpty
    }

    func consumePendingURLs() -> [URL] {
        defer { pendingURLs.removeAll() }
        return pendingURLs
    }

    private func scheduleOpenURLsFlush(application: NSApplication) {
        openURLsFlushTask?.cancel()
        openURLsFlushTask = Task { @MainActor [weak self, weak application] in
            try? await Task.sleep(for: .milliseconds(500))
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
        if let visibleWindow = application.windows.first(where: { $0.isVisible && !$0.isMiniaturized }) {
            guard application.isHidden else { return }
            application.unhide(nil)
            visibleWindow.orderFront(nil)
            return
        }

        application.activate(ignoringOtherApps: true)
        guard let window = application.windows.first else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
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
