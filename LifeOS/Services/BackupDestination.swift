import Foundation

/// The user-chosen folder that scheduled snapshots are written to.
///
/// Nothing here lives inside the app container: the folder is picked once through
/// the Files picker and re-opened through a security-scoped bookmark, so the files
/// survive LifeOS being deleted. The bookmark itself lives in `UserDefaults` and is
/// therefore lost on reinstall — the folder only has to be re-linked once, the
/// backups inside it are untouched.
enum BackupDestination {
    private static let bookmarkKey = "lifeos.backupFolderBookmark"
    private static let nameKey = "lifeos.backupFolderName"
    private static let pathKey = "lifeos.backupFolderPath"

    enum DestinationError: LocalizedError {
        case notConfigured
        case notReachable
        case readOnly

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Choose a backup folder in Settings first."
            case .notReachable:
                return "The backup folder can't be reached. Pick it again in Settings."
            case .readOnly:
                return "LifeOS can't write to that folder."
            }
        }
    }

    /// Folder name, e.g. `LifeOS Backups`.
    static var displayName: String? {
        UserDefaults.standard.string(forKey: nameKey)
    }

    /// Breadcrumb shown under the folder name, e.g. `iCloud Drive › LifeOS Backups`.
    static var displayPath: String? {
        UserDefaults.standard.string(forKey: pathKey)
    }

    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    // MARK: - Persistence

    static func store(url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
        UserDefaults.standard.set(displayPath(for: url), forKey: pathKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: pathKey)
    }

    // MARK: - Access

    static func resolve() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw DestinationError.notConfigured
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            throw DestinationError.notReachable
        }
        if isStale, let refreshed = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }

    /// Resolves the folder and keeps security-scoped access open for the duration of `body`.
    static func withAccess<T>(_ body: (URL) throws -> T) throws -> T {
        let url = try resolve()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    // MARK: - Diagnostics

    /// True when the picked folder is inside LifeOS's own sandbox, which means the
    /// files would still be destroyed with the app. Surfaced as a warning, not a block.
    static func isInsideAppSandbox(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        let sandboxRoots: [URL?] = [
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: NSTemporaryDirectory()),
        ]
        return sandboxRoots.compactMap { $0?.standardizedFileURL.path }.contains { root in
            target == root || target.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }

    private static func displayPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        if let range = path.range(of: "Mobile Documents/com~apple~CloudDocs") {
            let tail = path[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return tail.isEmpty ? "iCloud Drive" : "iCloud Drive › " + tail.replacingOccurrences(of: "/", with: " › ")
        }
        return url.deletingLastPathComponent().lastPathComponent + " › " + url.lastPathComponent
    }
}
