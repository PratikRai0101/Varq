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
        let coverImageData: Data? = {
            if let coverPath = package.coverPath,
               let data = try? extractDataWithFallback(from: archive, at: resolvedArchivePath(coverPath, relativeTo: packagePath)),
               isImageData(data) {
                return data
            }
            return scanArchiveForCoverImage(archive)
        }()

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

    private func extractDataWithFallback(from archive: Archive, at path: String) throws -> Data {
        do {
            return try extractData(from: archive, at: path)
        } catch EpubParserError.missingArchiveEntry {
            // Try case-insensitive match and filename-only match
            let lowerPath = path.lowercased()
            let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            for entry in archive where entry.path.lowercased() == lowerPath || entry.path.lowercased().hasSuffix("/" + fileName) {
                var data = Data()
                try archive.extract(entry) { chunk in
                    data.append(chunk)
                }
                return data
            }
            throw EpubParserError.missingArchiveEntry(path)
        }
    }

    private func isImageData(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        // JPEG
        if data[0] == 0xFF, data[1] == 0xD8 { return true }
        // PNG
        if data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 { return true }
        // GIF
        if data[0] == 0x47, data[1] == 0x49, data[2] == 0x46 { return true }
        // WebP (starts with RIFF....WEBP)
        if data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,
           data.count >= 12,
           data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50 {
            return true
        }
        // AVIF / HEIC (ftyp box)
        if data[4] == 0x66, data[5] == 0x74, data[6] == 0x79, data[7] == 0x70 { return true }
        return false
    }

    private func scanArchiveForCoverImage(_ archive: Archive) -> Data? {
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "avif"]
        // 1. Any image with "cover" in the path
        let coverCandidates = archive.filter { entry in
            let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
            let lowerPath = entry.path.lowercased()
            return imageExtensions.contains(ext) && lowerPath.contains("cover")
        }
        if let entry = coverCandidates.min(by: { $0.path.count < $1.path.count }) {
            var data = Data()
            try? archive.extract(entry) { chunk in
                data.append(chunk)
            }
            return data.isEmpty ? nil : data
        }
        // 2. Any image named like a cover (case-insensitive)
        let coverNames: Set<String> = ["cover", "titlepage", "front", " Jacket"]
        let nameCandidates = archive.filter { entry in
            let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
            let lowerName = entry.path.lowercased()
            return imageExtensions.contains(ext) && coverNames.contains(where: { lowerName.contains($0) })
        }
        if let entry = nameCandidates.min(by: { $0.path.count < $1.path.count }) {
            var data = Data()
            try? archive.extract(entry) { chunk in
                data.append(chunk)
            }
            return data.isEmpty ? nil : data
        }
        // 3. First image in the archive (last resort)
        if let entry = archive.first(where: {
            imageExtensions.contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased())
        }) {
            var data = Data()
            try? archive.extract(entry) { chunk in
                data.append(chunk)
            }
            return data.isEmpty ? nil : data
        }
        return nil
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
        let pathWithoutFragment = relativePath.split(separator: "#", maxSplits: 1).first.map(String.init) ?? relativePath
        let packageDirectory = packagePath
            .split(separator: "/")
            .dropLast()
            .joined(separator: "/")
        let absolutePath = "/" + packageDirectory + "/" + pathWithoutFragment
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
    let mediaType: String
}

private final class PackageDocumentDelegate: NSObject, XMLParserDelegate {
    private(set) var packageDocument = PackageDocument(title: nil, author: nil, coverPath: nil)

    private var title: String?
    private var author: String?
    private var coverIdentifier: String?
    private var manifestItems: [String: ManifestItem] = [:]
    private var guideCoverHref: String?
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
                properties: attributeDict["properties"] ?? "",
                mediaType: attributeDict["media-type"] ?? ""
            )
        case "reference" where attributeDict["type"] == "cover":
            guideCoverHref = attributeDict["href"]
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
        let coverPath = resolveCoverPath()
        packageDocument = PackageDocument(
            title: title,
            author: author,
            coverPath: coverPath
        )
    }

    private func resolveCoverPath() -> String? {
        // 1. EPUB 3 cover-image property on manifest item
        if let item = manifestItems.values.first(where: {
            $0.properties.split(separator: " ").contains("cover-image")
        }) {
            return item.href
        }

        // 2. EPUB 2 meta name="cover" referencing manifest item id
        if let id = coverIdentifier, let item = manifestItems[id] {
            return item.href
        }

        // 3. Guide reference with type="cover"
        if let href = guideCoverHref {
            return href
        }

        // 4. Fallback: manifest item with "cover" in its href and image-like media-type
        let imageMediaTypes: Set<String> = [
            "image/jpeg", "image/jpg", "image/png", "image/gif",
            "image/svg+xml", "image/webp", "image/avif"
        ]
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "svg", "webp", "avif"]
        if let item = manifestItems.values.first(where: {
            let lowerHref = $0.href.lowercased()
            return lowerHref.contains("cover") &&
                   (imageMediaTypes.contains($0.mediaType.lowercased()) ||
                    imageExtensions.contains(URL(fileURLWithPath: $0.href).pathExtension.lowercased()))
        }) {
            return item.href
        }

        // 5. Last resort: any manifest item with image media-type that contains "cover" in href
        if let item = manifestItems.values.first(where: {
            $0.href.lowercased().contains("cover")
        }) {
            return item.href
        }

        return nil
    }

    private func normalizedText(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
