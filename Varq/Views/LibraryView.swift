import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var libraryViewModel = LibraryViewModel()
    @State private var isDropTargeted = false

    let importViewModel: ImportViewModel

    var body: some View {
        NavigationStack {
            Group {
                if libraryViewModel.books.isEmpty {
                    ContentUnavailableView {
                        Label("Your library is waiting", systemImage: "books.vertical")
                    } description: {
                        Text("Import an EPUB, PDF, or CBZ to begin reading.")
                    } actions: {
                        Button("Import books", action: chooseFiles)
                            .buttonStyle(.borderedProminent)
                            .tint(.varqTerracotta)
                    }
                } else {
                    List(libraryViewModel.books) { book in
                        Text(book.title)
                    }
                }
            }
            .padding(VarqSpacing.large)
            .foregroundStyle(Color.varqInkLight)
            .background(isDropTargeted ? Color.varqParchmentDeep : .varqParchment)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import books", systemImage: "plus", action: chooseFiles)
                }
            }
        }
        .task { reloadLibrary() }
        .onDrop(of: ImportViewModel.supportedContentTypeIdentifiers, isTargeted: $isDropTargeted) { providers in
            Task {
                await importViewModel.importDroppedFiles(providers, into: modelContext)
                reloadLibrary()
            }
            return !providers.isEmpty
        }
        .alert("Some books could not be imported", isPresented: importErrorIsPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importViewModel.importErrors.map { "\($0.fileName): \($0.message)" }.joined(separator: "\n"))
        }
    }

    private var importErrorIsPresented: Binding<Bool> {
        Binding(
            get: { !importViewModel.importErrors.isEmpty },
            set: { isPresented in
                if !isPresented {
                    importViewModel.dismissImportErrors()
                }
            }
        )
    }

    private func chooseFiles() {
        let urls = importViewModel.chooseFiles()
        guard !urls.isEmpty else { return }

        Task {
            await importViewModel.importFiles(urls, into: modelContext)
            reloadLibrary()
        }
    }

    private func reloadLibrary() {
        do {
            try libraryViewModel.load(using: modelContext)
        } catch {
            // Import errors are displayed by ImportViewModel; a library reload failure leaves the current list intact.
        }
    }
}
