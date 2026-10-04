import Foundation
import WebKit
import ZIPFoundation

/// First-party, generated test book; no copyrighted publication content.
func makeIsolationEpub(in directory: URL, chapter: String, resources: [String: Data] = [:]) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("isolation.epub")
    let archive = try Archive(url: url, accessMode: .create)
    let entries: [String: Data] = [
        "mimetype": Data("application/epub+zip".utf8),
        "META-INF/container.xml": Data("""
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """.utf8),
        "OEBPS/content.opf": Data("""
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>
        """.utf8),
        "OEBPS/chapter.xhtml": Data(chapter.utf8)
    ].merging(resources) { _, resource in resource }
    for path in entries.keys.sorted() {
        guard let data = entries[path] else { continue }
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
            data.subdata(in: Int(position)..<(Int(position) + size))
        }
    }
    return url
}

@MainActor
final class EpubProbeSchemeHandler: NSObject, WKURLSchemeHandler {
    private(set) var requests: [URL] = []
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        requests.append(url)
        let data = Data("body { color: rgb(1, 2, 3); }".utf8)
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "text/css", expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) { }
}
