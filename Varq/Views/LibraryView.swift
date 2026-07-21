import Foundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var libraryViewModel = LibraryViewModel()
    @State private var isDropTargeted = false

    let importViewModel: ImportViewModel
    let managedLibraryDirectory: URL

    var body: some View {
        @Bindable var libraryViewModel = libraryViewModel

        NavigationStack {
            Group {
                if libraryViewModel.books.isEmpty {
                    LibraryEmptyState(importBooks: chooseFiles)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: VarqLayout.coverGridMinimumWidth), spacing: VarqSpacing.regular)],
                            spacing: VarqSpacing.large
                        ) {
                            ForEach(libraryViewModel.books) { book in
                                bookCard(for: book)
                            }
                        }
                    }
                }
            }
            .padding(VarqSpacing.large)
            .foregroundStyle(Color.varqInkLight)
            .background(isDropTargeted ? Color.varqParchmentDeep : .varqParchment)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem {
                    Picker("Sort books", selection: $libraryViewModel.sortOrder) {
                        ForEach(LibraryViewModel.SortOrder.allCases, id: \.self) { sortOrder in
                            Text(sortOrder.displayName).tag(sortOrder)
                        }
                    }
                    .pickerStyle(.menu)
                }

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

    @ViewBuilder
    private func bookCard(for book: Book) -> some View {
        switch book.format {
        case .epub:
            NavigationLink {
                ReaderView(book: book, bookURL: bookURL(for: book), renderer: EpubWebRenderer())
            } label: {
                BookCoverCard(book: book)
            }
            .buttonStyle(.plain)
        case .pdf:
            NavigationLink {
                ReaderView(book: book, bookURL: bookURL(for: book), renderer: PDFBookRenderer())
            } label: {
                BookCoverCard(book: book)
            }
            .buttonStyle(.plain)
        case .cbz:
            NavigationLink {
                ReaderView(book: book, bookURL: bookURL(for: book), renderer: CBZBookRenderer())
            } label: {
                BookCoverCard(book: book)
            }
            .buttonStyle(.plain)
        case .cbr:
            BookCoverCard(book: book)
                .accessibilityHint("CBR reading support is planned for a future release.")
        }
    }

    private func bookURL(for book: Book) -> URL {
        managedLibraryDirectory.appendingPathComponent(book.libraryRelativePath)
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
