import Foundation

enum OutputFolder {
    static func existingDirectory(from path: String, fileManager: FileManager = .default) -> URL? {
        guard !path.isEmpty else { return nil }
        return existingDirectory(at: URL(fileURLWithPath: path, isDirectory: true), fileManager: fileManager)
    }

    static func existingDirectory(at url: URL, fileManager: FileManager = .default) -> URL? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return url
    }
}
