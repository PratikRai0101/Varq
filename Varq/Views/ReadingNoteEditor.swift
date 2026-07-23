import SwiftUI

struct ReadingNoteEditor: View {
    let state: NoteEditorState
    let saveNote: (String, HighlightColorTag) -> Void
    let deleteNote: (ReadingNote) -> Void
    let cancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var noteText: String
    @State private var color: HighlightColorTag

    init(
        state: NoteEditorState,
        saveNote: @escaping (String, HighlightColorTag) -> Void,
        deleteNote: @escaping (ReadingNote) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.state = state
        self.saveNote = saveNote
        self.deleteNote = deleteNote
        self.cancel = cancel
        _noteText = State(initialValue: state.initialBody)
        _color = State(initialValue: state.initialColor)
    }

    var bodyView: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.regular) {
            Text(state.existingNote == nil ? "Add a note" : "Edit note")
                .font(VarqTypography.uiMedium(.headline))
                .foregroundStyle(foregroundColor)

            if let selectedText = state.selectedText {
                Text(selectedText)
                    .font(VarqTypography.reading())
                    .foregroundStyle(foregroundColor)
                    .lineLimit(3)
            } else {
                Text("Page note")
                    .font(VarqTypography.ui(.body))
                    .foregroundStyle(foregroundColor)
            }

            Menu {
                ForEach(HighlightColorTag.allCases, id: \.self) { option in
                    Button {
                        color = option
                    } label: {
                        Label(option.displayName, systemImage: color == option ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                Label("Note color: \(color.displayName)", systemImage: "paintpalette")
                    .foregroundStyle(color.varqColor)
            }

            TextEditor(text: $noteText)
                .font(VarqTypography.ui(.body))
                .accessibilityLabel("Note text")
                .scrollContentBackground(.hidden)
                .padding(VarqSpacing.compact)
                .background(colorScheme == .dark ? Color.varqIndigoLight : Color.varqParchmentDeep)

            HStack {
                if let note = state.existingNote {
                    Button("Delete note", role: .destructive) {
                        deleteNote(note)
                    }
                }
                Button("Cancel", role: .cancel, action: cancel)
                Spacer()
                Button("Save") {
                    saveNote(noteText, color)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VarqSpacing.large)
        .background(colorScheme == .dark ? Color.varqIndigo : Color.varqParchment)
        .frame(minWidth: VarqLayout.noteEditorMinimumWidth, minHeight: VarqLayout.noteEditorMinimumHeight)
    }

    var body: some View {
        bodyView
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? Color.varqInkDark : Color.varqInkLight
    }
}
