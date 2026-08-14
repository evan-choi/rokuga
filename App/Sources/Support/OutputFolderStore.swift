import Foundation
import SettingsKit

/// Resolves the recording destination: security-scoped bookmark when the user picked a folder, `~/Movies/Rokuga` otherwise (task 7.1 refines naming).
enum OutputFolderStore {
    static func currentFolder(settings: SettingsStore = .shared) -> URL {
        if let bookmark = settings.outputFolderBookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                if !stale { return url }
            }
        }
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let folder = movies.appendingPathComponent("Rokuga", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func setFolder(_ url: URL, settings: SettingsStore = .shared) {
        settings.outputFolderBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func newRecordingURL(settings: SettingsStore = .shared) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let baseName = "Rokuga \(formatter.string(from: Date()))"
        let folder = currentFolder(settings: settings)
        let ext = settings.containerFormat.fileExtension

        var candidate = folder.appendingPathComponent(baseName).appendingPathExtension(ext)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }
}
