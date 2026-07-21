# AGENTS.md — Varq

This file tells any coding agent (Claude Code, or similar) how to work in this repository. Read this before making changes. If anything here conflicts with a direct instruction from the person you're working with, the direct instruction wins — but flag the conflict rather than silently overriding this file.

## Project context

Varq is a native macOS e-reader app (Swift/SwiftUI, native macOS reader components, SwiftData). Full requirements live in `docs/PRD.md` — read it before starting any feature work. Design language lives in `docs/design-system.md` — read it before writing any View code.

## Setup commands

- Open the project: `open Varq.xcodeproj` (or `.xcworkspace` once SPM packages are added)
- Resolve Swift Package dependencies: File → Packages → Resolve Package Versions in Xcode, or `xcodebuild -resolvePackageDependencies`
- Build: `xcodebuild -scheme Varq -destination 'platform=macOS' build`
- Run tests: `xcodebuild -scheme Varq -destination 'platform=macOS' test`
- There is no separate package manager install step — Swift Package Manager dependencies are resolved through Xcode/xcodebuild directly.

## Project structure

```
Varq/
  Models/          SwiftData models (Book, Highlight, ReadingProgress, Shelf)
  Views/           SwiftUI views (LibraryView, ReaderView, BookCoverCard, etc.)
  ViewModels/       LibraryViewModel, ReaderViewModel — all business logic lives here, not in Views
  Services/        EpubParserService, ImportService, BiometricGateService, ExportService
  DesignSystem/    Color+Varq.swift, Typography.swift, shared reusable view modifiers
  Resources/       Assets.xcassets, fonts
docs/
  PRD.md
  design-system.md
  ARCHITECTURE.md
  BACKLOG.md
```

## Code style

- Swift 6 strict concurrency where feasible; mark `@MainActor` explicitly on ViewModels that touch UI state
- MVVM only — Views must not contain parsing, file I/O, or biometric logic directly; that all belongs in Services, orchestrated via ViewModels
- Prefer `async/await` over completion handlers for all new code
- No force-unwraps (`!`) in non-test code except where a prior guard/precondition makes it provably safe — comment why
- SwiftData models go in `Models/`, one type per file, matching the type name

## Design system discipline (read `docs/design-system.md` first)

- Never introduce a color, font, or spacing value that isn't defined in `DesignSystem/`. If a new visual need arises, add the token there first, then use it — don't inline hex values or literal point sizes in Views.
- Light mode background is warm parchment/cream (`Color.varqParchment`), never pure white (`Color.white`) or default `Color(.systemBackground)`. This is a deliberate brand decision, not an oversight if you see it flagged in review.
- Page-turn and transition animations should use warm-toned shadow variants, not system-default gray shadows.
- Do not add generic "Indian-themed" clip-art icons, flags, or literal cultural iconography. The visual language is: warm indigo/saffron/terracotta palette + restrained geometric motifs (see design-system.md for the specific palette and rationale) — elegant, not kitsch.
- Never copy, crop, or closely derive any shipped asset (icon, splash screen, illustration) from copyrighted reference artwork used for mood/inspiration during design (see `design-system.md`'s "Brand art assets — sourcing rules" section). If asked to add a new illustration or icon, use `docs/art-prompts.md` as the starting point for AI generation, or the original geometric motifs already defined in `design-system.md` — never source imagery directly from a reference painting or print.

## MVP scope discipline

Before implementing any feature, check `docs/PRD.md` section 7 (MVP scope) and section 8 (v1.1+ roadmap). If a request falls under section 8, implement it in an extensible way (don't hardcode assumptions that block it later) but do not build the full feature unless explicitly asked — flag that it's a v1.1+ item and confirm scope before proceeding.

Supported file formats for MVP: `.epub`, `.pdf`, `.cbz` only. CBR is deferred to v1.1+ (see `docs/PRD.md` section 8); MOBI/AZW3/FB2 conversion is also explicitly out of scope for MVP — do not add partial/broken support for these; either fully implement per an approved plan or leave them entirely unhandled with a clear "unsupported format" user-facing message.

## Testing instructions

- Every new Service and ViewModel needs corresponding unit tests in `VarqTests/`
- Run the full test suite before considering any task complete: `xcodebuild -scheme Varq -destination 'platform=macOS' test`
- For import/parsing logic, test against at least one real EPUB fixture (add small, permissively-licensed sample EPUBs to `VarqTests/Fixtures/` — do not commit copyrighted book content)
- UI-level changes: describe what to manually verify in the PR/commit message, since SwiftUI preview testing is the primary manual check available

## Sandboxing and entitlements

This app targets Mac App Store distribution and MUST run inside the App Sandbox. Any new file-system access must go through `NSOpenPanel`, drag-and-drop `NSItemProvider`, or security-scoped bookmarks — never assume unrestricted file-system access. If a feature seems to require broader entitlements, stop and flag it rather than silently adding an entitlement that could jeopardize App Store approval.

## Licensing

All first-party code is MIT licensed. When adding any third-party dependency via SPM, confirm its license is compatible (MIT/BSD/Apache-2.0 preferred; flag anything GPL-licensed before adding it, since it may conflict with Mac App Store distribution — do not add GPL dependencies without explicit sign-off).

## Commit granularity

- Treat one completed `docs/BACKLOG.md` checkbox as the default unit of work and one commit’s scope. Include that item’s directly required tests, fixtures, and backlog checkbox update in the same commit.
- A commit may span multiple files when they form one inseparable logical change (for example, a model and its relationship tests). Do not combine unrelated backlog items or opportunistic cleanup.
- Run the relevant tests and build **before** committing. Run the full `xcodebuild -scheme Varq -destination 'platform=macOS' test` suite before committing a completed task when the environment permits. Do not commit a known test failure; if an infrastructure issue prevents the full suite, run the strongest applicable checks and state the command and failure accurately in the commit body.
- Use an imperative, short subject line. In the commit body, identify the exact backlog work with: `Backlog: Phase N — <checkbox text>`. For work with no checklist item, write: `Backlog: none — <reason>`.
- Commit the completed, verified item **before starting the next backlog item**. Confirm that no uncommitted changes from the prior item remain; do not absorb unrelated pre-existing work into the new commit. This preserves a clean rollback point before each new item.

## Git / PR conventions

- Commit messages: imperative mood, short summary line, e.g. `Add EPUB cover extraction to ImportService`
- Keep commits scoped to one logical change
- Do not commit `.xcuserstate`, `DerivedData/`, or any local Xcode user-specific files — ensure `.gitignore` covers these
- Do not commit copyrighted book files, even for testing

## What to do when uncertain

If a requirement in `docs/PRD.md` is ambiguous, or a task isn't covered there, stop and ask rather than guessing at product intent — this is a personal/open-source project with a specific creative vision (see design-system.md), and silent assumptions are more costly to unwind than a clarifying question.
