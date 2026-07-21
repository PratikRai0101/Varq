import Foundation
import ZIPFoundation

struct CbzPage: Equatable, Sendable {
    let archivePath: String
    let fileURL: URL
}

struct CbzPublication: Equatable, Sendable {
    let rootDirectory: URL
    let pages: [CbzPage]
}

enum CbzPublicationError: Error, Equatable {
    case emptyArchive
    case unsafeArchivePath(String)
}

actor CbzPublicationService {
    private static let imageExtensions: Set<String> = ["avif", "gif", "jpeg", "jpg", "png", "webp"]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func extract(at cbzURL: URL, into rootDirectory: URL) throws -> CbzPublication {
        do {
            let archive = try Archive(url: cbzURL, accessMode: .read)
            let imageEntries = archive
                .filter { Self.imageExtensions.contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased()) }
                .sorted { $0.path.compare($1.path, options: .numeric) == .orderedAscending }
            guard !imageEntries.isEmpty else {
                throw CbzPublicationError.emptyArchive
            }

            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let pages = try imageEntries.map { entry in
                let destinationURL = try destinationURL(for: entry.path, in: rootDirectory)
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try archive.extract(entry, to: destinationURL)
                return CbzPage(archivePath: entry.path, fileURL: destinationURL)
            }
            return CbzPublication(rootDirectory: rootDirectory, pages: pages)
        } catch {
            try? fileManager.removeItem(at: rootDirectory)
            throw error
        }
    }

    func remove(_ publication: CbzPublication) throws {
        guard fileManager.fileExists(atPath: publication.rootDirectory.path) else {
            return
        }
        try fileManager.removeItem(at: publication.rootDirectory)
    }

    private func destinationURL(for archivePath: String, in rootDirectory: URL) throws -> URL {
        guard !archivePath.hasPrefix("/") else {
            throw CbzPublicationError.unsafeArchivePath(archivePath)
        }

        let standardizedRoot = rootDirectory.standardizedFileURL
        let destinationURL = standardizedRoot
            .appendingPathComponent(archivePath)
            .standardizedFileURL
        guard destinationURL.path.hasPrefix(standardizedRoot.path + "/") else {
            throw CbzPublicationError.unsafeArchivePath(archivePath)
        }
        return destinationURL
    }
}
