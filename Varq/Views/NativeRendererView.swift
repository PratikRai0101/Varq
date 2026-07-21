import AppKit
import SwiftUI

struct NativeRendererView: NSViewRepresentable {
    let rendererView: NSView

    func makeNSView(context: Context) -> NSView {
        rendererView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // The renderer owns its native view and updates it through BookRenderer navigation.
    }
}
