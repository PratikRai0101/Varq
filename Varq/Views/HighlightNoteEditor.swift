import SwiftUI

struct HighlightNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let highlight: Highlight
    let saveNote: (String) -> Void
    @State private var note: String

    init(highlight: Highlight, saveNote: @escaping (String) -> Void) {
        self.highlight = highlight
        self.saveNote = saveNote
        _note = State(initialValue: highlight.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.regular) {
            Text("Add a note")
                .font(VarqTypography.uiMedium(.headline))
                .foregroundStyle(Color.varqInkLight)

            Text(highlight.selectedText)
                .font(VarqTypography.reading())
                .foregroundStyle(Color.varqInkLight)
                .lineLimit(3)

            TextEditor(text: $note)
                .font(VarqTypography.ui(.body))
                .scrollContentBackground(.hidden)
                .padding(VarqSpacing.compact)
                .background(Color.varqParchmentDeep)

            HStack {
                Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                Spacer()
                Button("Save") {
                    saveNote(note)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VarqSpacing.large)
        .background(Color.varqParchment)
        .frame(minWidth: VarqLayout.noteEditorMinimumWidth, minHeight: VarqLayout.noteEditorMinimumHeight)
    }
}
