import Foundation

struct NoteEditorState: Identifiable {
    let id: UUID
    let anchor: ReadingNoteAnchor
    let selectedText: String?
    let existingNote: ReadingNote?
    let initialBody: String
    let initialColor: HighlightColorTag

    init(anchor: ReadingNoteAnchor) {
        id = UUID()
        self.anchor = anchor
        selectedText = anchor.selectedText
        existingNote = nil
        initialBody = ""
        initialColor = .saffron
    }

    init(note: ReadingNote, anchor: ReadingNoteAnchor) {
        id = note.id
        self.anchor = anchor
        selectedText = note.selectedText
        existingNote = note
        initialBody = note.body
        initialColor = HighlightColorTag(rawValue: note.colorTag) ?? .saffron
    }
}
