import AppKit
import Foundation

@MainActor
protocol ObsidianVaultFolderSelecting {
    func selectFolder() -> URL?
}

@MainActor
protocol ObsidianVaultBookmarkStoring {
    func save(_ url: URL) throws
    func resolve() throws -> URL?
}

@MainActor
final class ObsidianVaultDestinationService: ObsidianVaultFolderSelecting, ObsidianVaultBookmarkStoring {
    private let defaults: UserDefaults
    private let bookmarkKey = "obsidianVaultBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose the Obsidian vault folder for Varq exports. Varq writes only to its Varq subfolder."
        panel.prompt = "Use this vault"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try save(url)
            return url
        } catch {
            return nil
        }
    }

    func save(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
    }

    func resolve() throws -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { try save(url) }
        return url
    }
}
