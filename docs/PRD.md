# Varq — Product Requirements Document

**Status:** Draft v1.0
**Owner:** Pratik Rai
**Platform:** macOS (native), iOS port planned post-v1
**Last updated:** 2026-07-22

---

## 1. Summary

Varq (वर्क़/ورق — "leaf" or "page" in Hindi/Urdu, also the term for the decorative gold/silver foil used in Indian sweets and art) is a native, open-source e-reader for macOS that combines the format breadth of tools like Calibre/Icecream Book Reader with the visual polish and animation quality of Apple Books. It is built entirely in Swift/SwiftUI (no Electron/web-wrapper), uses native macOS reader components as its rendering engine, and carries a distinct visual identity inspired by Indian art and design traditions rather than generic reader-app aesthetics.

The long-term vision includes an iOS companion app, iCloud sync, an on-device AI reading assistant via Apple's Foundation Models framework, and a Touch ID-gated private shelf.

## 2. Goals

- Ship a fast, native MVP to the Mac App Store within a short iteration cycle
- Differentiate visually and functionally from Apple Books (locked formats) and Calibre (dated UI)
- Build an open-source project with real community traction (GitHub stars, HN/Reddit visibility)
- Establish a design language distinct enough to be recognizable as "Varq" — Indian-art-influenced, not generic minimalism

## 3. Non-goals (for v1)

- Windows/Linux support
- DRM'd file support (Kindle AZW DRM, Adobe DE)
- Full OPDS server/client
- Cloud sync (deferred to v1.1+ via CloudKit)
- Social/sharing features
- Monetization mechanics (deferred decision)

## 4. Target users

- Power readers who currently juggle Apple Books + Calibre because neither does everything
- Students / researchers who want Markdown/Obsidian-exportable highlights
- Manga/comic readers who want native CBZ support without a separate app; CBR support is planned for v1.1+
- Open-source-minded Mac users who want to inspect/trust the code they read books in

## 5. Tech stack

| Layer | Choice | Rationale |
|---|---|---|
| Language | Swift 6 | Native performance, modern concurrency |
| UI | SwiftUI (macOS 15+ target) | Fluid animations, native feel, less boilerplate than AppKit |
| Book engine | Native macOS reader components (WebKit, PDFKit, format-specific archive decoding) | Preserves a native macOS target while isolating each format behind a reader-engine boundary |
| Persistence | SwiftData | Native, modern, low-boilerplate local DB |
| Architecture | MVVM | Clean separation of parsing/business logic from views |
| Biometrics | LocalAuthentication + CryptoKit + Keychain | Touch ID-gated private shelf with real encryption, not just UI hiding |
| AI (v1.1+) | Foundation Models framework | On-device summarization/lookup, zero API cost under Small Business Program |
| Sync (v1.1+) | CloudKit | Free infra, native iCloud account integration |

## 6. Licensing

MIT License for all first-party code. Avoids the GPL/App Store distribution ambiguity entirely. Any third-party dependency must use an App Store-compatible license. Free binary distributed on the Mac App Store; source available on GitHub for anyone to build themselves.

## 7. MVP scope (v1.0)

### 7.1 Import & library
- Drag-and-drop import of .epub, .pdf, .cbz (CBR deferred to v1.1+ — see section 8)
- Auto-extraction of title, author, cover image on import
- Duplicate detection (hash-based) on import
- Grid library view with cover art, sortable by title/author/date added/recently read

### 7.2 Reader
- Paginated EPUB/PDF rendering via the native macOS reader engine
- Page turns via arrow keys, trackpad swipe, and click zones
- Remembers exact scroll/page position per book, per device
- Adjustable typography: font family (2–3 curated choices), size, line height, margins
- Light mode (cream/parchment background, not pure white) and dark/sepia night mode
- CBZ mode: right-to-left toggle, dual-page spread, page-fit options. CBR is deferred to v1.1+ — see 'CBR deferral' note in section 8.

### 7.3 Notes & highlights
- Text selection → persistent highlight, with the Varq accent and neon highlight palette
- Separate personal notes attached to selected text or the current reader location, with clickable citation-like markers and hover summaries
- Export highlights/notes to Markdown (Obsidian/Notion/plain-MD compatible) and JSON

### 7.4 Private shelf (Touch ID)
- Designate any book(s) as private
- LocalAuthentication-gated access (Touch ID / password fallback per system policy)
- Underlying files encrypted at rest via CryptoKit, key stored in Keychain

### 7.5 Design system
- Full implementation of the Varq visual identity (see `docs/design-system.md`)
- Custom page-turn animation (warm-toned shadow, not default system gray)
- Custom app icon and launch experience

## 8. v1.1+ roadmap (not in MVP scope, but agents should architect for extensibility)

- CBR (RAR-based comic archive) support. Deferred from MVP — see 'CBR deferral' note below.
- MOBI/AZW3/FB2 → EPUB auto-conversion on import
- Metadata auto-scraper (Open Library / Google Books API)
- On-device AI: chapter summaries, vocabulary lookup, Q&A via Foundation Models
- Handoff + iCloud sync (CloudKit)
- Bionic reading / RSVP mode
- OPDS server
- Reading stats/streaks (local only)
- Siri / Shortcuts / App Intents integration
- iOS companion app

CBR deferral (2026-07-21): CBR support requires an unrar decoder, since RAR is a proprietary compression format. Research found two viable Swift options — UnrarKit (BSD-2 wrapper, no SPM support, last released 2022) and Unrar.swift (MIT wrapper, SPM-native, actively maintained) — but both bundle RARLab's UnRAR C source, which carries its own separate, non-SPDX 'freeware' license (permissive for reading/extracting RAR archives, restricted only around recreating the proprietary RAR compression algorithm). This license is genuinely usable — many shipped Mac/iOS apps rely on it — but it doesn't fit cleanly into standard OSS license auditing, and this ambiguity wasn't worth blocking MVP delivery over. Decision: ship CBZ-only for v1.0; revisit CBR in v1.1+ using Unrar.swift specifically (not UnrarKit, for its better maintenance and native SPM support), once real usage data indicates it's worth the residual licensing ambiguity.

## 9. Success metrics

- Successful App Store review approval on first or second submission
- GitHub: organic stars/forks within first month of open-sourcing
- Functional TestFlight beta with 5–10 real users prior to public submission
- No sandbox violations or crash-on-launch issues in review

## 10. Risks

| Risk | Mitigation |
|---|---|
| Institutional Apple Developer account access could be revoked | Confirm ownership terms; keep a personal Apple ID as fallback path; document bundle ID/team ownership clearly |
| Native reader-engine complexity underestimated | Validate each format adapter behind the reader-engine boundary before custom ReaderView work begins; prioritize the PDFKit path and prove EPUB/comic viability with small fixtures |
| MOBI/AZW3 conversion has no clean native Swift solution | Explicitly deferred out of MVP; revisit with a bundled conversion binary or server-side approach later |
| Scope creep from the large v1.1+ feature list | AGENTS.md and task backlog enforce MVP-first discipline |

## 11. Open questions

- App name confirmed as **Varq** (वर्क़/ورق — "leaf/page" in Hindi/Urdu, also the term for the gold/silver decorative foil used in Indian sweets and art). Chosen over "Folio" (taken on the App Store) and other Indic candidates (Panna, Pustak, Kitaab, Adhyay — all crowded/collided with existing apps in the reading category). Availability was checked via web search only; final confirmation happens when the app record is created in App Store Connect.
- Free vs. paid vs. freemium App Store pricing model
- Whether GPL is reconsidered later for stronger copyleft guarantees (would require legal reconfirmation)
