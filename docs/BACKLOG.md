# Varq — MVP Task Backlog

Ordered roughly by dependency. An agent picking up work should generally proceed top-to-bottom within a phase, but should confirm current state against the actual repo first — this list may drift from reality as work progresses.

## Phase 0 — Project scaffold
- [x] Create Xcode project: macOS App, SwiftUI interface, SwiftData storage, macOS 15+ deployment target
- [x] Establish the native macOS reader-engine boundary; defer format adapters until their viability is proven (see `docs/adr/0001-use-a-native-macos-reader-engine.md`)
- [x] Set up folder structure per `docs/ARCHITECTURE.md` (Models/Views/ViewModels/Services/DesignSystem)
- [x] Add `.gitignore` for Xcode (`DerivedData/`, `.xcuserstate`, `*.xcuserdatad/`)
- [x] Add MIT `LICENSE` file
- [x] Configure App Sandbox entitlement from the start (not retrofitted later)

## Phase 1 — Design system foundation
- [x] Implement `DesignSystem/Color+Varq.swift` with all tokens from `docs/design-system.md`
- [x] Implement `DesignSystem/Typography.swift` (UI font + reading serif definitions)
- [ ] Generate/finalize original brand art using `docs/art-prompts.md` (splash screen, app icon exploration, empty-state illustration) — verify each output against the sourcing rules in `design-system.md` before use
- [x] Build app icon from the compass mark motif (see `design-system.md` motif study), refined using the app icon generation prompt if a richer version is wanted
- [x] Verify light/dark mode both render correctly against the color table

## Phase 2 — Data models
- [x] Implement `Book`, `ReadingProgress`, `Highlight` SwiftData models per `ARCHITECTURE.md`
- [x] Write unit tests for model relationships and basic persistence

## Phase 3 — Import pipeline
- [x] `ImportService`: EPUB import via the native EPUB parser, extract title/author/cover
- [x] `ImportService`: PDF import via PDFKit
- [x] `ImportService`: CBZ import (archive extraction + first-page-as-cover)
- CBR import is deferred to v1.1+; see the CBR deferral decision in `docs/PRD.md` section 8.
- [x] Duplicate detection via content hash
- [x] Drag-and-drop target on LibraryView + `NSOpenPanel` fallback
- [x] Unit tests against fixture files in `VarqTests/Fixtures/` (small, permissively-licensed samples only)

## Phase 4 — Library view
- [x] `LibraryViewModel`: fetch/sort/filter books
- [x] `LibraryView`: responsive grid, cover art, title/author labels
- [x] Empty state (no books imported yet) matching design system voice/tone
- [x] Sort controls (title, author, date added, recently read)

## Phase 5 — Reader view core
- [x] `ReaderViewModel`: coordinates the reader engine, exposes current reading locator/position
- [x] `ReaderView`: paginated rendering, arrow key + trackpad swipe navigation
- [x] Persist reading position to `ReadingProgress` on navigation/close
- [x] Typography controls (font size, line height, margins) wired to live re-render
- [x] Light / dark / sepia page-tone modes (independent toggle per `design-system.md`)
- [x] Custom warm-toned page-turn animation

## Phase 6 — CBZ comics/manga mode
- [x] CBZ-specific reader path (image sequence, not the text reader engine)
- [x] Right-to-left toggle
- [x] Dual-page spread option
- [x] Page-fit options (fit width / fit height / actual size)

## Phase 7 — Highlights & notes
- [x] Text selection → highlight creation UI (toolbar and contextual color picker from the design-system palette)
- [x] Separate personal notes on selected text or reader locations, with clickable citation markers and hover summaries
- [x] `Highlight` list view per book
- [x] `ExportService`: Markdown export (Obsidian-compatible frontmatter)
- [x] `ExportService`: JSON export
- [x] Unit tests for export format correctness

## Phase 8 — Private shelf (Touch ID)
- [x] `BiometricGateService`: LocalAuthentication wrapper
- [x] Mark-as-private UI flow
- [x] CryptoKit encryption at rest + Keychain-stored key with biometric access control
- [x] Session-based unlock behavior
- [x] Manual security review pass before considering this feature complete — this is the highest-stakes feature in the app from a trust standpoint

## Phase 9 — Polish & pre-submission
- [x] Full pass against `docs/design-system.md` — flag any screen that doesn't match the reference mockup's warmth/restraint balance
- [x] Accessibility pass (VoiceOver labels, reduceMotion fallback for page-turn animation, Dynamic Type where applicable)
- [ ] App Store screenshots and listing copy
- [ ] TestFlight distribution to 5–10 real users
- [ ] Address TestFlight feedback
- [ ] Submit for App Store review

## Explicitly out of scope for this backlog (v1.1+, see PRD section 8)
CBR support (unless `docs/PRD.md`'s CBR deferral decision has been revisited), MOBI/AZW3/FB2 conversion, metadata auto-scraper, on-device AI features, CloudKit sync/Handoff, bionic reading/RSVP, OPDS, reading stats, Siri/Shortcuts/App Intents, iOS app. Do not pull these into the active backlog without updating `PRD.md` first.
