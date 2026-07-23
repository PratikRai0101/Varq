import SwiftUI

struct TableOfContentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.varqDarkTheme) private var darkTheme

    let entries: [ReaderTableOfContentsEntry]
    let selectEntry: (ReaderTableOfContentsEntry) -> Void

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button(entry.title) {
                    selectEntry(entry)
                }
                .foregroundStyle(colorScheme == .dark ? darkTheme.primaryText : Color.varqInkLight)
            }
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? darkTheme.background : Color.varqParchment)
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
