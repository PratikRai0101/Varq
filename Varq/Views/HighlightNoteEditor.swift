import SwiftUI

struct HighlightNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
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
                .foregroundStyle(colorScheme == .dark ? Color.varqInkDark : Color.varqInkLight)

            Text(highlight.selectedText)
                .font(VarqTypography.reading())
                .foregroundStyle(colorScheme == .dark ? Color.varqInkDark : Color.varqInkLight)
                .lineLimit(3)

            TextEditor(text: $note)
                .font(VarqTypography.ui(.body))
                .scrollContentBackground(.hidden)
                .padding(VarqSpacing.compact)
                .background(colorScheme == .dark ? Color.varqIndigoLight : Color.varqParchmentDeep)

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
        .background(colorScheme == .dark ? Color.varqIndigo : Color.varqParchment)
        .frame(minWidth: VarqLayout.noteEditorMinimumWidth, minHeight: VarqLayout.noteEditorMinimumHeight)
    }
}
