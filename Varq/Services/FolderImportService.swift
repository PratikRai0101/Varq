import Foundation

struct FolderImportIssue {
    let url: URL
    let message: String
}

struct FolderImportDiscovery {
    let files: [URL]
    let issues: [FolderImportIssue]
}

/// Adapter for the transient permission granted by a system folder chooser.
@MainActor
protocol FolderSecurityScopeAccessing {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

@MainActor
private struct SystemFolderSecurityScope: FolderSecurityScopeAccessing {
    func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

/// External filesystem boundary; Foundation's Swift enumeration wrapper is not overridable.
@MainActor
protocol FolderDirectoryEnumerating {
    func enumerator(at url: URL, errorHandler: @escaping (URL, any Error) -> Bool) -> FileManager.DirectoryEnumerator?
}

@MainActor
private struct SystemFolderDirectoryEnumerator: FolderDirectoryEnumerating {
    func enumerator(at url: URL, errorHandler: @escaping (URL, any Error) -> Bool) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, errorHandler: errorHandler)
    }
}

@MainActor
final class FolderImportService {
    private let directoryEnumerator: any FolderDirectoryEnumerating
    private let securityScope: any FolderSecurityScopeAccessing

    init(directoryEnumerator: (any FolderDirectoryEnumerating)? = nil, securityScope: (any FolderSecurityScopeAccessing)? = nil) {
        self.directoryEnumerator = directoryEnumerator ?? SystemFolderDirectoryEnumerator()
        self.securityScope = securityScope ?? SystemFolderSecurityScope()
    }

    /// Keep the parent folder grant alive through discovery AND every awaited child import.
    /// A false start result is not proof of denied access: sandbox-owned URLs need no grant.
    func withBooks(in directoryURL: URL, perform: (FolderImportDiscovery) async throws -> Void) async throws {
        let accessed = securityScope.startAccessing(directoryURL)
        defer { if accessed { securityScope.stopAccessing(directoryURL) } }
        guard directoryURL.isFileURL else { throw FolderImportError.invalidFolder }
        let rootValues = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw FolderImportError.invalidFolder
        }
        var issues: [FolderImportIssue] = []
        guard let enumerator = directoryEnumerator.enumerator(
            at: directoryURL,
            errorHandler: { url, error in
                issues.append(FolderImportIssue(url: url, message: error.localizedDescription))
                return true // Continue with other readable branches.
            }
        ) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let supportedExtensions = Set([BookFormat.epub.rawValue, BookFormat.pdf.rawValue, BookFormat.cbz.rawValue])
        var files: [URL] = []
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    issues.append(FolderImportIssue(url: url, message: FolderImportError.symbolicLink.localizedDescription))
                    continue
                }
                if values.isRegularFile == true, supportedExtensions.contains(url.pathExtension.lowercased()) {
                    files.append(url)
                }
            } catch {
                enumerator.skipDescendants()
                issues.append(FolderImportIssue(url: url, message: error.localizedDescription))
            }
        }
        try await perform(FolderImportDiscovery(files: files.sorted { $0.path < $1.path }, issues: issues))
    }
}

private enum FolderImportError: LocalizedError {
    case invalidFolder
    case symbolicLink

    var errorDescription: String? {
        switch self {
        case .invalidFolder: "Choose a regular folder to import. Symbolic links are not followed."
        case .symbolicLink: "Symbolic links are not followed during folder import."
        }
    }
}
