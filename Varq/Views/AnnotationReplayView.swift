import SwiftUI

struct AnnotationReplayView: View {
    let highlights: [Highlight]
    let openHighlight: (Highlight) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.large) {
            HStack {
                Text("Review annotations")
                    .font(VarqTypography.uiMedium(.title2))
                Spacer()
                Button("Done", action: dismiss.callAsFunction)
            }
            if let highlight = orderedHighlights[safe: index] {
                Text(highlight.selectedText)
                    .font(VarqTypography.reading())
                    .textSelection(.enabled)
                    .padding(VarqSpacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.varqParchmentDeep)
                    .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.compact))
                if let note = highlight.note, !note.isEmpty {
                    Text(note).font(VarqTypography.ui(.body))
                }
                HStack {
                    Button("Previous") { index = max(index - 1, 0) }.disabled(index == 0)
                    Button("Open in reader") { openHighlight(highlight); dismiss() }
                    Spacer()
                    Button("Next") { index = min(index + 1, orderedHighlights.count - 1) }.disabled(index >= orderedHighlights.count - 1)
                }
            } else {
                ContentUnavailableView("No annotations yet", systemImage: "highlighter", description: Text("Add highlights to review them here."))
            }
        }
        .padding(VarqSpacing.large)
        .frame(minWidth: VarqLayout.noteEditorMinimumWidth, minHeight: VarqLayout.noteEditorMinimumHeight)
        .background(Color.varqParchment)
    }

    private var orderedHighlights: [Highlight] { highlights.sorted { $0.dateCreated < $1.dateCreated } }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
