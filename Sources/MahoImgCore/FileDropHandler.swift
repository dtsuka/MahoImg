import Foundation
import UniformTypeIdentifiers

enum FileDropHandler {
    static func accepts(providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    }

    @MainActor
    static func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            if let url = await loadURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    @MainActor
    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                continuation.resume(returning: resolveURL(from: item))
            }
        }
    }

    private static func resolveURL(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let url = item as? URL {
            return url
        }
        return nil
    }
}
