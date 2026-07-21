import Foundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var libraryViewModel = LibraryViewModel()
    @State private var isDropTargeted = false
    @State private var privateBookViewModel = PrivateBookViewModel()
    @State private var bookToDelete: Book?

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
        .alert("Delete \"\(bookToDelete?.title ?? "")\"?", isPresented: deleteConfirmationIsPresented) {
            Button("Cancel", role: .cancel) { bookToDelete = nil }
            Button("Delete", role: .destructive) { performDelete() }
        } message: {
            Text("This book and its reading progress will be permanently removed.")
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
            .contextMenu { privateBookMenu(for: book) }
        case .pdf:
            NavigationLink {
                ReaderView(book: book, bookURL: bookURL(for: book), renderer: PDFBookRenderer())
            } label: {
                BookCoverCard(book: book)
            }
            .buttonStyle(.plain)
            .contextMenu { privateBookMenu(for: book) }
        case .cbz:
            NavigationLink {
                ReaderView(book: book, bookURL: bookURL(for: book), renderer: CBZBookRenderer())
            } label: {
                BookCoverCard(book: book)
            }
            .buttonStyle(.plain)
            .contextMenu { privateBookMenu(for: book) }
        case .cbr:
            BookCoverCard(book: book)
                .accessibilityHint("CBR reading support is planned for a future release.")
        }
    }

    @ViewBuilder
    private func privateBookMenu(for book: Book) -> some View {
        if !book.isPrivate {
            Button("Mark as private", systemImage: "lock") {
                privateBookViewModel.markPrivate(
                    book: book,
                    managedFileURL: bookURL(for: book),
                    using: modelContext
                )
            }
        }

        Button("Delete book", systemImage: "trash", role: .destructive) {
            bookToDelete = book
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

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { bookToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    bookToDelete = nil
                }
            }
        )
    }

    private func performDelete() {
        guard let book = bookToDelete else { return }
        let fileURL = bookURL(for: book)

        modelContext.delete(book)
        try? modelContext.save()
        try? FileManager.default.removeItem(at: fileURL)

        bookToDelete = nil
        reloadLibrary()
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
