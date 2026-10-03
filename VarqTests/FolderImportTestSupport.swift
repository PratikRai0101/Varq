import Foundation
@testable import Varq

/// Inject OS enumeration failures, rather than relying on chmod behavior on the test host.
@MainActor
final class FolderTestDirectoryEnumerator: FolderDirectoryEnumerating {
    var inaccessibleURL: URL?
    var failEnumeration = false

    func enumerator(at url: URL, errorHandler: @escaping (URL, any Error) -> Bool) -> FileManager.DirectoryEnumerator? {
        if failEnumeration { return nil }
        if let inaccessibleURL { _ = errorHandler(inaccessibleURL, CocoaError(.fileReadNoPermission)) }
        return FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, errorHandler: errorHandler)
    }
}
