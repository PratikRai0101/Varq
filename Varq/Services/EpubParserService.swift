import Foundation
import ZIPFoundation

struct EpubMetadata: Equatable, Sendable {
    let title: String
    let author: String
    let coverImageData: Data?
}

actor EpubParserService {
    func parse(at fileURL: URL) throws -> EpubMetadata {
        let archive = try Archive(url: fileURL, accessMode: .read)
        let containerData = try extractData(from: archive, at: "META-INF/container.xml")
        let packagePath = try parsePackagePath(from: containerData)
        let packageData = try extractData(from: archive, at: packagePath)
        let package = try parsePackage(from: packageData)
        let coverImageData = try package.coverPath.map {
            try extractData(from: archive, at: resolvedArchivePath($0, relativeTo: packagePath))
        }

        return EpubMetadata(
            title: package.title ?? fileURL.deletingPathExtension().lastPathComponent,
            author: package.author ?? "Unknown Author",
            coverImageData: coverImageData
        )
    }

    private func extractData(from archive: Archive, at path: String) throws -> Data {
        guard let entry = archive[path] else {
            throw EpubParserError.missingArchiveEntry(path)
        }

        var data = Data()
        try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    private func parsePackagePath(from containerData: Data) throws -> String {
        let delegate = ContainerDocumentDelegate()
        try parseXML(containerData, using: delegate)

        guard let packagePath = delegate.packagePath else {
            throw EpubParserError.missingPackageDocument
        }
        return packagePath
    }

    private func parsePackage(from packageData: Data) throws -> PackageDocument {
        let delegate = PackageDocumentDelegate()
        try parseXML(packageData, using: delegate)
        return delegate.packageDocument
    }

    private func parseXML(_ data: Data, using delegate: XMLParserDelegate) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw EpubParserError.invalidXML
        }
    }

    private func resolvedArchivePath(_ relativePath: String, relativeTo packagePath: String) -> String {
        let packageDirectory = packagePath
            .split(separator: "/")
            .dropLast()
            .joined(separator: "/")
        let absolutePath = "/" + packageDirectory + "/" + relativePath
        return URL(fileURLWithPath: absolutePath)
            .standardizedFileURL
            .path
            .dropFirst()
            .description
    }
}

private enum EpubParserError: Error {
    case invalidXML
    case missingArchiveEntry(String)
    case missingPackageDocument
}

private final class ContainerDocumentDelegate: NSObject, XMLParserDelegate {
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

private struct PackageDocument {
    let title: String?
    let author: String?
    let coverPath: String?
}

private struct ManifestItem {
    let href: String
    let properties: String
}

private final class PackageDocumentDelegate: NSObject, XMLParserDelegate {
    private(set) var packageDocument = PackageDocument(title: nil, author: nil, coverPath: nil)

    private var title: String?
    private var author: String?
    private var coverIdentifier: String?
    private var manifestItems: [String: ManifestItem] = [:]
    private var activeTextElement: String?
    private var activeText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "dc:title", "title":
            activeTextElement = "title"
            activeText = ""
        case "dc:creator", "creator":
            activeTextElement = "author"
            activeText = ""
        case "meta" where attributeDict["name"] == "cover":
            coverIdentifier = attributeDict["content"]
        case "item":
            guard let identifier = attributeDict["id"], let href = attributeDict["href"] else {
                return
            }
            manifestItems[identifier] = ManifestItem(
                href: href,
                properties: attributeDict["properties"] ?? ""
            )
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        activeText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let activeTextElement else {
            return
        }

        switch (activeTextElement, elementName) {
        case ("title", "dc:title"), ("title", "title"):
            title = normalizedText(activeText)
            self.activeTextElement = nil
        case ("author", "dc:creator"), ("author", "creator"):
            author = normalizedText(activeText)
            self.activeTextElement = nil
        default:
            break
        }

    }

    func parserDidEndDocument(_ parser: XMLParser) {
        let coverItem = manifestItems.values.first {
            $0.properties.split(separator: " ").contains("cover-image")
        } ?? coverIdentifier.flatMap { manifestItems[$0] }
        packageDocument = PackageDocument(
            title: title,
            author: author,
            coverPath: coverItem?.href
        )
    }

    private func normalizedText(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
