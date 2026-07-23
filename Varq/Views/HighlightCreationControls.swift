import SwiftUI

struct HighlightCreationControls: View {
    let createHighlight: (HighlightColorTag) -> Void

    var body: some View {
        Menu("Highlight selection", systemImage: "highlighter") {
            ForEach(HighlightColorTag.allCases, id: \.self) { color in
                Button {
                    createHighlight(color)
                } label: {
                    HStack {
                        Circle()
                            .fill(swatchColor(for: color))
                            .frame(width: VarqSpacing.compact, height: VarqSpacing.compact)
                        Text(color.displayName)
                    }
                }
            }
        }
        .accessibilityHint("Select text in the reader, then choose a highlight color.")
        .help("Highlight selected text")
    }

    private func swatchColor(for color: HighlightColorTag) -> Color {
        color.varqColor
    }
}
