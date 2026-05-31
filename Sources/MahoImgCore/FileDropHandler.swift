import Foundation
import UniformTypeIdentifiers

enum FileDropHandler {
    static let fileURLTypeIdentifiers = [UTType.fileURL.identifier]
    static let folderDropTypeIdentifiers = [UTType.fileURL.identifier, UTType.folder.identifier]

    static func accepts(
        providers: [NSItemProvider],
        typeIdentifiers: [String] = fileURLTypeIdentifiers
    ) -> Bool {
        providers.contains { provider in
            typeIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }
    }

    @MainActor
    static func loadURLs(
        from providers: [NSItemProvider],
        typeIdentifiers: [String] = fileURLTypeIdentifiers
    ) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadURL(from: provider, typeIdentifiers: typeIdentifiers) {
                urls.append(url)
            }
        }
        return urls
    }

    @MainActor
    private static func loadURL(from provider: NSItemProvider, typeIdentifiers: [String]) async -> URL? {
        for typeIdentifier in typeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let url = await loadURL(from: provider, typeIdentifier: typeIdentifier) {
                return url
            }
        }
        return nil
    }

    @MainActor
    private static func loadURL(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
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
