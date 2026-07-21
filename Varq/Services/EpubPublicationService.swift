import Foundation
import ZIPFoundation

struct EpubSpineResource: Equatable, Sendable {
    let href: String
    let fileURL: URL
}

struct EpubPublication: Equatable, Sendable {
    let rootDirectory: URL
    let spine: [EpubSpineResource]
}

enum EpubPublicationError: Error, Equatable {
    case missingPackageDocument
    case missingSpineResource(String)
    case emptySpine
    case unsafeArchivePath(String)
    case invalidXML
}

actor EpubPublicationService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func extract(at epubURL: URL, into rootDirectory: URL) throws -> EpubPublication {
        do {
            let archive = try Archive(url: epubURL, accessMode: .read)
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

            for entry in archive {
                let destinationURL = try destinationURL(for: entry.path, in: rootDirectory)
                if entry.path.hasSuffix("/") {
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                } else {
                    try fileManager.createDirectory(
                        at: destinationURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try archive.extract(entry, to: destinationURL)
                }
            }

            let packagePath = try packagePath(in: rootDirectory)
            let spineReferences = try spineReferences(
                in: rootDirectory.appendingPathComponent(packagePath)
            )
            guard !spineReferences.isEmpty else {
                throw EpubPublicationError.emptySpine
            }

            let spine = try spineReferences.map { reference in
                let archivePath = resolvedArchivePath(reference.href, relativeTo: packagePath)
                let resourceURL = rootDirectory.appendingPathComponent(archivePath)
                guard fileManager.fileExists(atPath: resourceURL.path) else {
                    throw EpubPublicationError.missingSpineResource(reference.href)
                }
                return EpubSpineResource(href: reference.href, fileURL: resourceURL)
            }
            return EpubPublication(rootDirectory: rootDirectory, spine: spine)
        } catch {
            try? fileManager.removeItem(at: rootDirectory)
            throw error
        }
    }

    func remove(_ publication: EpubPublication) throws {
        guard fileManager.fileExists(atPath: publication.rootDirectory.path) else {
            return
        }
        try fileManager.removeItem(at: publication.rootDirectory)
    }

    private func destinationURL(for archivePath: String, in rootDirectory: URL) throws -> URL {
        guard !archivePath.hasPrefix("/") else {
            throw EpubPublicationError.unsafeArchivePath(archivePath)
        }

        let standardizedRoot = rootDirectory.standardizedFileURL
        let destinationURL = standardizedRoot
            .appendingPathComponent(archivePath)
            .standardizedFileURL
        guard destinationURL.path.hasPrefix(standardizedRoot.path + "/") else {
            throw EpubPublicationError.unsafeArchivePath(archivePath)
        }
        return destinationURL
    }

    private func packagePath(in rootDirectory: URL) throws -> String {
        let containerURL = rootDirectory.appendingPathComponent("META-INF/container.xml")
        let delegate = EpubContainerDelegate()
        try parseXML(Data(contentsOf: containerURL), using: delegate)
        guard let packagePath = delegate.packagePath else {
            throw EpubPublicationError.missingPackageDocument
        }
        return packagePath
    }

    private func spineReferences(in packageURL: URL) throws -> [EpubSpineReference] {
        let delegate = EpubPackageDelegate()
        try parseXML(Data(contentsOf: packageURL), using: delegate)
        return delegate.spineReferences
    }

    private func parseXML(_ data: Data, using delegate: XMLParserDelegate) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw EpubPublicationError.invalidXML
        }
    }

    private func resolvedArchivePath(_ href: String, relativeTo packagePath: String) -> String {
        let resourcePath = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        let packageURL = URL(fileURLWithPath: "/" + packagePath)
        return packageURL
            .deletingLastPathComponent()
            .appendingPathComponent(resourcePath)
            .standardizedFileURL
            .path
            .dropFirst()
            .description
    }
}

private final class EpubContainerDelegate: NSObject, XMLParserDelegate {
    private(set) var packagePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "rootfile" else {
            return
        }
        packagePath = attributeDict["full-path"]
    }
}

private struct EpubSpineReference {
    let href: String
}

private final class EpubPackageDelegate: NSObject, XMLParserDelegate {
    private var manifest: [String: String] = [:]
    private var spineIDs: [String] = []

    var spineReferences: [EpubSpineReference] {
        spineIDs.compactMap { identifier in
            manifest[identifier].map(EpubSpineReference.init(href:))
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "item":
            guard let identifier = attributeDict["id"], let href = attributeDict["href"] else {
                return
            }
            manifest[identifier] = href
        case "itemref":
            guard let identifier = attributeDict["idref"] else {
                return
            }
            spineIDs.append(identifier)
        default:
            break
        }
    }
}
