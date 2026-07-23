# Varq post-MVP roadmap

**Status:** Planned. This document orders approved post-MVP work; it is not a release-date commitment.

## Product commitments

- Retain macOS 15 as Varq’s deployment target. Apple Intelligence UI is additive and isolated to macOS 26+ devices where the system model is available.
- Start with Local Intelligence. Apple Private Cloud Compute (PCC) is a future, separate opt-in; it is not required for reading or local intelligence.
- A Private Book is excluded from indexes and PCC by default. Local Intelligence requires an explicit per-book confirmation; see [ADR 0009](adr/0009-keep-private-content-local-by-default.md).
- Keep exports portable and local-first. Obsidian Vault Export precedes direct Notion integration.
- Do not add CBR, conversion, sync, networking, or community features until their prerequisite release has demonstrated value and passed its security/privacy review.

## Release sequence

### v1.1 — Local reading intelligence and knowledge export

**Goal:** make a reader’s own library more useful without an account, API key, or remote service.

1. **Intelligence foundation**
   - Introduce a deep `AIAssistantService` module. Its interface accepts a bounded reading context and a requested aid, not an arbitrary caller-provided prompt.
   - Add a system-model availability adapter, macOS 26 availability isolation, locale/error handling, and deterministic test adapters.
   - Define Generated Reading Aid presentation, copy, and explicit-save behavior. A generated response never silently becomes a note.
   - Use Apple’s Evaluations framework for quality and regression cases on supported development machines.
2. **Selected-passage aids**
   - Explain, simplify, summarize, and generate discussion questions from a selected passage.
   - Keep the native dictionary lookup as the primary deterministic definition action.
3. **Chapter recap**
   - Generate a short recap, key ideas, and optional reflection questions from the current EPUB chapter.
   - Add PDF text extraction only when it can be bounded and source locations remain clear.
4. **Visible-page explanation**
   - Analyze an explicitly selected PDF/CBZ page or crop with on-device image input and OCR.
   - Label output as generated and potentially inaccurate.
5. **Obsidian Vault Export**
   - Let the reader choose an output folder with `NSOpenPanel` and persist a security-scoped bookmark only with consent.
   - Export stable Markdown files with YAML frontmatter, durable Varq IDs, and deterministic filenames.
   - Create only canonical wikilinks: Book → Collection, Author, and its Reading Artifacts. Do not infer semantic links or edit unrelated vault files.
   - Write only below a dedicated `Varq/` directory in the chosen vault; exports are idempotent and never delete or rewrite user-authored files.
   - Provide a Notion-ready Markdown export profile, but no Notion account connection yet.
6. **Local reader value**
   - Annotation replay, reading-session timing, estimated time remaining, and optional local goals/streaks.

**Exit criteria:** AI unavailable states are graceful; private-content policy tests pass; selected-passage and recap evaluation cases meet agreed quality thresholds; an Obsidian export can be repeated without duplicating or overwriting user files.

### v1.2 — Discovery, automation, and grounded Q&A

**Goal:** make existing content easy to find and act on while preserving local control.

1. Index book metadata and, only with a setting, Reading Artifact text in Core Spotlight.
2. Model Book and Collection as App Entities.
3. Add App Intents for Open Book, Resume Current Book, Search Library, Add Bookmark, and Create Note.
4. Add View Annotations for the current Book and visible library items after App Entities are reliable.
5. Add AppIntentsTesting coverage for entity lookup, indexing, navigation, and view annotations.
6. Add **Ask this chapter** using retrieval over bounded, indexed chapter chunks. Every answer shows tappable source excerpts/locations.

**Exit criteria:** index updates and deletions are verified; private content is never indexed without the required consent; every Q&A answer is grounded in returned source material.

### v1.3 — Reader and library depth

**Goal:** expand core reading and library capability without adding accounts.

1. Bionic reading and RSVP, each independently optional and accessibility-reviewed.
2. Metadata lookup with explicit network/privacy UX, incorrect-match recovery, and licensed-cover rules.
3. CBR support using the selected UnRAR approach only after another license review.
4. Investigate MOBI/AZW3/FB2 conversion; ship only after a sandbox-safe, App-Store-compatible solution is approved.
5. Add documented export profiles for Logseq/Roam where they can be faithfully represented as local files.

### v1.4 — Cross-device foundation

**Goal:** establish personal continuity before social features.

1. iOS companion reader foundation.
2. Handoff for the current Book and locator.
3. CloudKit sync for library metadata, progress, Reading Artifacts, and Collections.
4. Define conflict resolution, deletion semantics, migration, and private-book key behavior before enabling sync.

### v2 — Optional services and community

**Goal:** add online capability only where its benefit exceeds its operational and privacy cost.

1. PCC escalation for larger-context/reasoning requests, subject to Small Business Program eligibility, entitlement, quotas, availability, and explicit opt-in.
2. Third-party language-model adapters only with a provider-specific authentication, billing, and data-flow design.
3. Direct Notion integration after OAuth, token storage, sync direction, failure recovery, and deletion semantics are designed. Local Notion-ready Markdown remains available regardless.
4. OPDS server, only after sandbox/networking, local-network discovery, authentication, and lifecycle requirements are designed.
5. Reading groups/shared annotations, only with an account, authorization, moderation, and backend plan.

## Dependency rules

- Spotlight indexing precedes full-library or chapter Q&A.
- App Entities precede View Annotations.
- iOS precedes meaningful Handoff; conflict resolution precedes CloudKit sync.
- Stable local export schemas precede direct PKM-service integrations.
- No remote model provider is a fallback for unavailable Local Intelligence unless the reader explicitly enables that provider.

## Explicitly not planned

A Focus Filter does not suppress other apps’ notifications and is not a Varq feature. Generic whole-book chat without retrieval and source locations is also excluded.
