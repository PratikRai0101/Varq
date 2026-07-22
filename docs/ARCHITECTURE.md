# Varq — Architecture Notes

Supplementary to `PRD.md`. This covers implementation-level decisions an agent needs before writing code, so architectural choices don't have to be re-derived or guessed at each session.

## Pattern: MVVM

- **Models** (`Models/`): SwiftData `@Model` classes only. No business logic beyond computed properties directly derived from stored properties.
- **ViewModels** (`ViewModels/`): `@MainActor @Observable` classes. Own all state a View needs, call into Services for anything involving file I/O, parsing, or biometrics. Views should be near-trivial — if a View has more than a few lines of logic beyond layout, that logic likely belongs in the ViewModel.
- **Services** (`Services/`): Stateless (or minimally-stateful) classes/actors that do the actual work — parsing EPUBs, importing files, encrypting private-shelf content, exporting highlights. Services should be independently testable without any SwiftUI dependency.
- **Views** (`Views/`): SwiftUI only. Read from ViewModels via `@State`/`@Bindable`. No direct SwiftData queries in Views beyond simple `@Query` for straightforward list display — anything requiring filtering/sorting logic beyond trivial cases goes through a ViewModel.

## Core models (initial shape — refine during implementation)

```swift
@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var coverImageData: Data?
    var libraryRelativePath: String // relative path inside Varq's managed library
    var contentHash: String // SHA-256 digest used for duplicate detection
    var format: BookFormat // enum: epub, pdf, cbz, cbr
    var dateAdded: Date
    var isPrivate: Bool
    var readingProgress: ReadingProgress?
    var highlights: [Highlight]
    var notes: [ReadingNote]
}

@Model
final class ReadingProgress {
    var id: UUID
    var book: Book?
    var locatorData: Data // Reading locator, serialized
    var lastReadDate: Date
    var percentComplete: Double
}

@Model
final class Highlight {
    var id: UUID
    var book: Book?
    var locatorData: Data // versioned TextHighlightAnchor for the selection
    var selectedText: String
    var colorTag: String // maps to a design-system highlight color
    var dateCreated: Date
}

@Model
final class ReadingNote {
    var id: UUID
    var book: Book?
    var anchorData: Data // versioned ReadingNoteAnchor for selected text or current location
    var selectedText: String?
    var body: String
    var colorTag: String // maps to a design-system marker color
    var dateCreated: Date
    var dateModified: Date
}
```

Book file handling must account for App Sandbox constraints — `ImportService` uses the user's temporary security-scoped access only to copy a book into Varq's managed library. Persist the managed copy's relative path, never an external path or security-scoped bookmark.

## Reader engine boundary

- Keep each supported format behind a native macOS reader-engine component: PDFKit for PDFs, WebKit plus EPUB parsing for EPUBs, and archive image decoding for CBZ comics.
- Follow `docs/adr/0003-use-css-columns-for-epub-pagination.md` for the `BookRenderer` interface and the versioned `BookLocator` schema. `ReaderViewModel` coordinates that interface; it must not expose WebKit or PDFKit types to SwiftData models or Views.
- `BookLocator` is the canonical serialized representation of "where in the book" for `ReadingProgress`. `Highlight` stores the separate, versioned `TextHighlightAnchor` contract from `docs/adr/0004-store-text-highlights-as-versioned-range-anchors.md`; EPUB anchors are exact and PDFs persist normalized selection geometry per `docs/adr/0007-store-normalized-pdf-selection-geometry.md`. `ReadingNote` stores the separate, versioned `ReadingNoteAnchor` contract from `docs/adr/0008-model-reading-notes-separately-from-highlights.md`.
- Validate EPUB and CBZ navigation with small permissively licensed fixtures before building a custom `ReaderView`. CBR is deferred to v1.1+ under the decision recorded in `docs/PRD.md` section 8.

## Import pipeline

1. User drags a file in, or picks via `NSOpenPanel` (sandboxed-safe)
2. `ImportService` detects format by extension + file signature (don't trust extension alone)
3. For EPUB/PDF: the relevant native reader-engine component parses metadata (title, author, cover)
4. For CBZ/CBR: `ImportService` extracts the archive, treats each image as a page, derives a cover from the first image
5. Compute a content hash for duplicate detection before finalizing the import
6. Copy the file into the app's sandboxed container (`Application Support/Varq/Library/`) — do not rely on the original file staying in place, since the user may move or delete it

## Private shelf (Touch ID) implementation notes

See `docs/adr/0006-encrypt-private-books-before-marking-them-private.md`: encryption and the private flag are one atomic workflow; a private managed copy is never plaintext at rest.

1. `BiometricGateService` wraps `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`
2. On marking a book private: generate a symmetric key via CryptoKit, encrypt the book's file content at rest, store the key in Keychain with `kSecAttrAccessControl` requiring biometric presence
3. On access attempt: prompt Touch ID → on success, decrypt into a temporary in-memory buffer for the reader engine to read from (avoid writing decrypted plaintext back to disk)
4. Session-based unlock: once unlocked, keep the private shelf visible/accessible for the remainder of the app session (or a configurable timeout) rather than re-prompting per book

## Export pipeline

- `ExportService` converts `Highlight`, `ReadingNote`, and associated `Book` metadata into: (a) a Markdown file with YAML frontmatter (Obsidian-compatible), (b) a flat JSON structure, on demand
- Keep the Markdown template itself as a separate, easily-editable string template — this will likely need iteration based on real Obsidian/Notion user feedback post-launch

## Testing strategy

- `Services/` layer: full unit test coverage, since this is where correctness matters most (parsing, encryption, export format correctness)
- `ViewModels/`: unit test the state transitions and logic, mocking Services
- `Views/`: rely on SwiftUI Previews for visual verification; describe manual verification steps in commit messages rather than attempting brittle UI snapshot tests for MVP

## Deferred architecture decisions (v1.1+, do not build against these yet)

- CloudKit sync will require adding a sync-conflict resolution strategy to `ReadingProgress` and `Highlight` — don't build assumptions today that would block adding a `lastModified`/CRDT-style merge strategy later
- Foundation Models integration will likely live in a new `Services/AIAssistantService.swift` — keep `ReaderViewModel` decoupled enough that this can be added without a major refactor
