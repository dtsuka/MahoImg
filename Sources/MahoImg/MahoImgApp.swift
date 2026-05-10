import SwiftUI

@main
struct MahoImgApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("MahoImg") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
    }
}

