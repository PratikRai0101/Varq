import Foundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var libraryViewModel = LibraryViewModel()
    @State private var isDropTargeted = false
    @State private var privateBookViewModel = PrivateBookViewModel()
    @State private var bookToDelete: Book?
    @State private var bookToRename: Book?
    @State private var renameTitle = ""
    @State private var renameAuthor = ""
    @State private var newCollectionName = ""
    @State private var isAddingCollection = false
    @State private var bookToRefresh: Book?
    @State private var isPrivateBookErrorPresented = false
    @State private var isSettingsPresented = false

    let importViewModel: ImportViewModel
    let managedLibraryDirectory: URL

    var body: some View {
        @Bindable var libraryViewModel = libraryViewModel

        NavigationSplitView {
            sidebar
        } detail: {
            libraryGrid
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
        .alert("New collection", isPresented: $isAddingCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { newCollectionName = "" }
            Button("Create") {
                guard !newCollectionName.isEmpty else { return }
                libraryViewModel.createCollection(named: newCollectionName, using: modelContext)
                newCollectionName = ""
            }
        } message: {
            Text("Enter a name for the new collection.")
        }
        .alert("Rename book", isPresented: renameAlertIsPresented) {
            TextField("Title", text: $renameTitle)
            TextField("Author", text: $renameAuthor)
            Button("Cancel", role: .cancel) {
                bookToRename = nil
                renameTitle = ""
                renameAuthor = ""
            }
            Button("Save") {
                performRename()
            }
        } message: {
            Text("Edit the title and author for this book.")
        }
        .alert("Could not mark as private", isPresented: $isPrivateBookErrorPresented) {
            Button("OK", role: .cancel) {
                privateBookViewModel.clearError()
            }
        } message: {
            Text(privateBookViewModel.errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
    }

    private var sidebar: some View {
        List {
            Section("Collections") {
                ForEach(libraryViewModel.collections) { collection in
                    Button {
                        libraryViewModel.selectedCollection = collection
                    } label: {
                        Label(collection.name, systemImage: iconForCollection(collection))
                            .foregroundStyle(libraryViewModel.selectedCollection?.id == collection.id ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let collection = libraryViewModel.collections[index]
                        libraryViewModel.deleteCollection(collection, using: modelContext)
                    }
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem {
                Button("New collection", systemImage: "folder.badge.plus") {
                    isAddingCollection = true
                }
            }
        }
    }

    private var libraryGrid: some View {
        Group {
            if libraryViewModel.allBooks.isEmpty {
                LibraryEmptyState(importBooks: chooseFiles)
            } else if libraryViewModel.books.isEmpty {
                collectionEmptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: VarqLayout.coverGridMinimumWidth), spacing: VarqSpacing.regular)],
                        spacing: VarqSpacing.large
                    ) {
                        ForEach(libraryViewModel.books) { book in
                            bookCard(for: book)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(VarqSpacing.large)
        .foregroundStyle(colorScheme == .dark ? Color.varqInkDark : Color.varqInkLight)
        .background(isDropTargeted ? (colorScheme == .dark ? Color.varqIndigoLight : Color.varqParchmentDeep) : (colorScheme == .dark ? Color.varqIndigo : Color.varqParchment))
        .navigationTitle(libraryViewModel.selectedCollection?.name ?? "Library")
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
                    Button("Import books", systemImage: "plus") {
                        chooseFiles()
                    }
                }
                ToolbarItem {
                    Button("Import folder", systemImage: "folder.badge.plus") {
                        chooseFolder()
                    }
                }
                ToolbarItem {
                    Button("Settings", systemImage: "gearshape") {
                        isSettingsPresented = true
                    }
                }
        }
    }

    private var collectionEmptyState: some View {
        VStack(spacing: VarqSpacing.regular) {
            Image(systemName: "tray")
                .font(VarqTypography.ui(.largeTitle))
                .foregroundStyle(Color.varqSaffron)

            Text("No books in \(libraryViewModel.selectedCollection?.name ?? "this collection")")
                .font(VarqTypography.uiMedium(.title2))
                .foregroundStyle(Color.varqInkDark)

            Text("Books that match this collection will appear here.")
                .font(VarqTypography.ui(.body))
                .foregroundStyle(Color.varqParchmentDeep)
                .multilineTextAlignment(.center)
        }
        .padding(VarqSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconForCollection(_ collection: BookCollection) -> String {
        switch collection.name {
        case "All": "books.vertical"
        case "Currently Reading": "book.open"
        case "Want to Read": "bookmark"
        case "Finished": "checkmark.circle"
        case "Favorites": "heart"
        default: "folder"
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
            .contextMenu { bookMenu(for: book) }
        case .pdf:
            NavigationLink {
                ReaderView(book: book, bookURL: bookURL(for: book), renderer: PDFBookRenderer())
            } label: {
                BookCoverCard(book: book)
            }
            .buttonStyle(.plain)
            .contextMenu { bookMenu(for: book) }
        case .cbz:
            NavigationLink {
                ReaderView(book: book, bookURL: bookURL(for: book), renderer: CBZBookRenderer())
            } label: {
                BookCoverCard(book: book)
            }
            .buttonStyle(.plain)
            .contextMenu { bookMenu(for: book) }
        case .cbr:
            BookCoverCard(book: book)
                .accessibilityHint("CBR reading support is planned for a future release.")
        }
    }

    @ViewBuilder
    private func bookMenu(for book: Book) -> some View {
        if book.isPrivate {
            Button("Unmark as private", systemImage: "lock.open") {
                privateBookViewModel.unmarkPrivate(
                    book: book,
                    managedFileURL: bookURL(for: book),
                    using: modelContext
                )
                if privateBookViewModel.errorMessage != nil {
                    isPrivateBookErrorPresented = true
                }
            }
        } else {
            Button("Mark as private", systemImage: "lock") {
                privateBookViewModel.markPrivate(
                    book: book,
                    managedFileURL: bookURL(for: book),
                    using: modelContext
                )
                if privateBookViewModel.errorMessage != nil {
                    isPrivateBookErrorPresented = true
                }
            }
        }

        Menu("Add to collection") {
            ForEach(libraryViewModel.collections.filter { $0.name != "All" }) { collection in
                let isInCollection = book.collections?.contains(where: { $0.id == collection.id }) ?? false
                Button {
                    if isInCollection {
                        libraryViewModel.removeBook(book, from: collection, using: modelContext)
                    } else {
                        libraryViewModel.addBook(book, to: collection, using: modelContext)
                    }
                } label: {
                    Label(
                        collection.name,
                        systemImage: isInCollection ? "checkmark" : "plus"
                    )
                }
            }
        }

        if book.format == .epub || book.format == .pdf {
            Button("Refresh metadata", systemImage: "arrow.clockwise") {
                Task { await refreshMetadata(for: book) }
            }
        }

        Button("Rename", systemImage: "pencil") {
            bookToRename = book
            renameTitle = book.title
            renameAuthor = book.author
        }

        Button("Delete book", systemImage: "trash", role: .destructive) {
            bookToDelete = book
        }
    }

    private func refreshMetadata(for book: Book) async {
        let fileURL = bookURL(for: book)
        let parser = EpubParserService()
        do {
            let metadata = try await parser.parse(at: fileURL)
            book.title = metadata.title
            book.author = metadata.author
            book.coverImageData = metadata.coverImageData
            try? modelContext.save()
            reloadLibrary()
        } catch {
            // Silently ignore refresh failures; the book keeps its old metadata.
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

    private var renameAlertIsPresented: Binding<Bool> {
        Binding(
            get: { bookToRename != nil },
            set: { isPresented in
                if !isPresented {
                    bookToRename = nil
                    renameTitle = ""
                    renameAuthor = ""
                }
            }
        )
    }

    private func performRename() {
        guard let book = bookToRename else { return }
        let trimmedTitle = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = renameAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            book.title = trimmedTitle
        }
        if !trimmedAuthor.isEmpty {
            book.author = trimmedAuthor
        }
        try? modelContext.save()
        bookToRename = nil
        renameTitle = ""
        renameAuthor = ""
        reloadLibrary()
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

    private func chooseFolder() {
        let urls = importViewModel.chooseFiles(allowDirectories: true)
        guard let directory = urls.first else { return }
        Task {
            await importViewModel.importDirectory(directory, into: modelContext)
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
