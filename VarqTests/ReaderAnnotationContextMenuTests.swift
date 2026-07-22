import AppKit
import PDFKit
import Testing
@testable import Varq

@MainActor
struct ReaderAnnotationContextMenuTests {
    @Test func exposesHighlightPaletteAndNoteActions() {
        let target = ContextMenuTarget()
        let items = ReaderAnnotationContextMenu.items(
            target: target,
            highlightAction: #selector(ContextMenuTarget.highlight(_:)),
            removeHighlightAction: #selector(ContextMenuTarget.removeHighlight(_:)),
            noteAction: #selector(ContextMenuTarget.note(_:)),
            pageNoteAction: #selector(ContextMenuTarget.pageNote(_:))
        )

        #expect(items.map(\.title) == ["Highlight", "Remove highlight", "Add note…", "Add page note…"])
        #expect(items.first?.submenu?.items.map(\.title) == [
            "Saffron", "Terracotta", "Maroon", "Neon green", "Neon yellow", "Neon red", "Neon pink"
        ])
        #expect(items.first?.submenu?.items.compactMap { $0.representedObject as? String } == [
            "saffron", "terracotta", "maroon", "highlightGreen", "highlightYellow", "highlightRed", "highlightPink"
        ])
    }

    @Test func opensANoteWhenPdfKitReportsAMarkerHit() async {
        let view = ReaderPDFView(frame: .zero)
        let noteID = UUID()
        var openedNoteID: UUID?
        view.noteMarkerHandler = { openedNoteID = $0 }

        let annotation = PDFAnnotation(bounds: .zero, forType: .text, withProperties: nil)
        annotation.userName = "varq-note:\(noteID.uuidString)"
        NotificationCenter.default.post(
            name: .PDFViewAnnotationHit,
            object: view,
            userInfo: ["PDFAnnotationHit": annotation]
        )
        await Task.yield()

        #expect(openedNoteID == noteID)
    }
}

@MainActor
private final class ContextMenuTarget: NSObject {
    @objc func highlight(_ sender: NSMenuItem) { }
    @objc func removeHighlight(_ sender: NSMenuItem) { }
    @objc func note(_ sender: NSMenuItem) { }
    @objc func pageNote(_ sender: NSMenuItem) { }
}
