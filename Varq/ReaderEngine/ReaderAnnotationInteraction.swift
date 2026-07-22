import AppKit
import Foundation

@MainActor
enum ReaderAnnotationAction {
    case createHighlight(anchor: TextHighlightAnchor, color: HighlightColorTag)
    case removeHighlight(anchor: TextHighlightAnchor)
    case createNote(anchor: TextHighlightAnchor)
    case createPageNote(locator: BookLocator)
}

@MainActor
protocol ReaderAnnotationInteractionProviding: AnyObject {
    func setAnnotationActionHandler(_ handler: @escaping (ReaderAnnotationAction) -> Void)
    func setNoteActivationHandler(_ handler: @escaping (UUID) -> Void)
}

@MainActor
enum ReaderAnnotationContextMenu {
    static func items(
        target: AnyObject,
        highlightAction: Selector,
        removeHighlightAction: Selector,
        noteAction: Selector,
        pageNoteAction: Selector
    ) -> [NSMenuItem] {
        let highlightMenu = NSMenu()
        for color in HighlightColorTag.allCases {
            let item = NSMenuItem(
                title: color.displayName,
                action: highlightAction,
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = color.rawValue
            highlightMenu.addItem(item)
        }

        let highlightItem = NSMenuItem(title: "Highlight", action: nil, keyEquivalent: "")
        highlightItem.submenu = highlightMenu

        let removeHighlightItem = NSMenuItem(
            title: "Remove highlight",
            action: removeHighlightAction,
            keyEquivalent: ""
        )
        removeHighlightItem.target = target

        let noteItem = NSMenuItem(title: "Add note…", action: noteAction, keyEquivalent: "")
        noteItem.target = target

        let pageNoteItem = NSMenuItem(title: "Add page note…", action: pageNoteAction, keyEquivalent: "")
        pageNoteItem.target = target
        return [highlightItem, removeHighlightItem, noteItem, pageNoteItem]
    }
}
