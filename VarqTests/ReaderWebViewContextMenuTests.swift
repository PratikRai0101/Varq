import AppKit
import Testing
import WebKit
@testable import Varq

@MainActor
struct ReaderWebViewContextMenuTests {
    @Test func insertsVarqActionsIntoTheWebKitProvidedMenu() throws {
        let webView = ReaderWebView()
        webView.varqContextMenuItemsProvider = {
            [
                NSMenuItem(title: "Highlight", action: nil, keyEquivalent: ""),
                NSMenuItem(title: "Add note…", action: nil, keyEquivalent: ""),
                NSMenuItem(title: "Add page note…", action: nil, keyEquivalent: "")
            ]
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Look Up", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy", action: nil, keyEquivalent: ""))
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        webView.willOpenMenu(menu, with: event)

        #expect(menu.items.map(\.title) == [
            "Highlight", "Add note…", "Add page note…", "", "Look Up", "Copy"
        ])
    }
}
