import SwiftUI

struct TableOfContentsView: View {
    @Environment(\.dismiss) private var dismiss

    let entries: [ReaderTableOfContentsEntry]
    let selectEntry: (ReaderTableOfContentsEntry) -> Void

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button(entry.title) {
                    selectEntry(entry)
                }
                .foregroundStyle(Color.varqInkDark)
            }
            .navigationTitle("Contents")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .frame(
            minWidth: VarqLayout.noteEditorMinimumWidth,
            minHeight: VarqLayout.noteEditorMinimumHeight
        )
    }
}
