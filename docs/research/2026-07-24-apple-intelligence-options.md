# Apple Intelligence and macOS options for Varq

**Researched:** 2026-07-24

**Scope:** What Varq can add without a third-party model provider, plus constraints that matter for a local macOS reader.

## Verified platform facts

- The Foundation Models framework now supports the on-device Apple Foundation Model, direct image attachments, Vision OCR/barcode tools, a model-provider abstraction, and a Spotlight-backed RAG tool. [What’s new in the Foundation Models framework (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/241/)
- The on-device model is private, works offline, and has no per-request charge; it is **not universal**. It requires an Apple-Intelligence-capable device, a supported region/language, Apple Intelligence enabled, and downloaded model assets. Apps must check `SystemLanguageModel.availability` and handle unavailable states. [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) · [availability guidance](https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models)
- Foundation Models is available from macOS 26. Varq’s current macOS 15 minimum must remain supported with `@available(macOS 26.0, *)` feature isolation and a non-AI fallback.
- Private Cloud Compute (PCC) is not billed per token for qualifying developers, but it is not zero-setup: the developer must be in the Small Business Program, have fewer than two million first-time downloads across its apps, obtain the PCC entitlement, and handle device availability, connectivity, and per-person quota limits. [PCC eligibility](https://developer.apple.com/private-cloud-compute/) · [PCC integration and quotas (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/319/)
- The new `LanguageModel` abstraction makes provider packages possible, but a Claude/Gemini provider is not automatically free; its provider, authentication, data handling, and pricing remain separate decisions. [Bring an LLM provider (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/339/)
- App Intents can expose app content and actions to Siri, Shortcuts, and Spotlight. WWDC26 adds View Annotations and AppIntentsTesting. [macOS WWDC26 guide](https://developer.apple.com/wwdc26/guides/macos/) · [AppIntentsTesting (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/295/)
- Core Spotlight indexes are on-device and private to the device owner. On macOS, a Spotlight importer plugin—not a file-import extension—is needed for arbitrary custom file indexing; Varq can instead index the app-managed entities it owns with Core Spotlight. [Core Spotlight](https://developer.apple.com/documentation/corespotlight)
- A Focus Filter changes **Varq’s own behavior** when a Focus is active. It cannot globally suppress notifications from other apps, so “silence notifications while reading” is not a meaningful Varq feature. [SetFocusFilterIntent](https://developer.apple.com/documentation/appintents/setfocusfilterintent)

## Recommended sequence

### 1. On-device selected-passage tools — low-to-medium effort, no service cost

Add a reader context-menu submenu, available only when `SystemLanguageModel` is ready:

- **Explain this passage**
- **Summarize selection**
- **Make this simpler**
- **Create discussion questions**

Keep each request single-turn, use only the selected passage plus a small explicit instruction, and return structured output. This is private/offline on eligible Macs and avoids full-book retrieval complexity. Keep the existing system dictionary lookup as the non-AI choice; do not replace a deterministic definition with a generative answer.

**Guardrails:** label output as generated, never invent citations, provide “Copy” rather than silently saving generated text, and do not send a private book’s content anywhere.

### 2. Chapter recap — medium effort, no service cost

Offer an explicit “Chapter recap” after a chapter is completed: short summary, key ideas, and optional reflection questions. Limit input to the current EPUB chapter or a bounded PDF text extraction. Keep it opt-in and cache only when the person chooses to save it. This is the best first summary feature because its scope is clear and evaluable.

### 3. Spotlight for library metadata and user-authored annotations — medium effort, no AI required

Index book title, author, collection, and optionally highlight/note text. Open the exact book/highlight when a result is selected. Exclude private books by default; make indexing annotation text an explicit setting because it becomes searchable outside the app. This improves ordinary Spotlight immediately and creates the retrieval foundation for later grounded Q&A.

### 4. App Intents: Open, resume, and find a book — medium effort, no AI model cost

Model `Book` and perhaps `Collection` as App Entities. Start with foreground actions: **Open Book**, **Resume Current Book**, and **Search Library**. Test queries and indexing through AppIntentsTesting. Add View Annotations only after these entities exist: the reader can then identify “this book”; identifying arbitrary paragraphs needs a deliberate, privacy-reviewed paragraph entity model.

### 5. Grounded “Ask this chapter” — medium-to-high effort

Do this only after a retrieval layer exists. Chunk current-chapter text, retrieve a small set of passages, and show the returned answer with tappable source excerpts/locations. For a full-library feature, use a privacy-scoped Core Spotlight index and `SpotlightSearchTool`; private books must be excluded unless a person explicitly opts in to local indexing.

Do **not** ship generic chat over an entire book with the book pasted into the prompt: the on-device context is limited, results will be ungrounded, and the app cannot show trustworthy source locations.

### 6. Diagram/page explanation — medium effort, eligible Macs only

For PDFs and CBZ, let a person explicitly ask about the displayed page or a cropped region. Render the page/crop to an image and attach it to a Foundation Models request; use the Vision OCR tool for dense text. This is more useful and safer than adding camera capture. Clearly say that image explanations can be mistaken.

## Worth doing without AI

- **Annotation replay:** a chronological, filterable reading journal built from the existing Highlight and ReadingNote data.
- **Reading goals and streaks:** local-only, optional, and calculated from existing progress; no account or service needed.
- **Native library/full-text search:** start with title/author/notes/highlights, then add indexed book text only with a clear privacy setting.
- **Reading-session timer and estimated time remaining:** deterministic, local, and useful even on unsupported Macs.
- **App Intent/Shortcut actions:** open/resume a book, add/remove a bookmark, create a note, and add a book to a collection.
- **Improved exports:** a stable Markdown format plus a documented JSON schema; avoid direct Notion integration until OAuth, failure handling, and privacy expectations are accepted.

## Defer or treat as non-free

- **PCC:** excellent future escalation path, but requires eligibility, entitlement, quota UI, and an online privacy disclosure.
- **Third-party Claude/Gemini integration:** not free by default; it needs keys/OAuth, provider terms, a data-flow disclosure, and a fallback.
- **CloudKit sync/Handoff:** Handoff requires an iOS companion to create user value; sync requires conflict resolution, migrations, deletion semantics, and private-book key design.
- **OPDS server and reading groups:** networking, authentication, and long-running/background behavior make them substantial features.
- **Metadata scraping:** network dependency, incorrect-match handling, and cover-image licensing are product/privacy work, not a quick free win.
- **MOBI/AZW3/FB2 conversion and CBR:** remain explicitly out of MVP scope and have format/licensing complexity.

## Product recommendation

Make **selected-passage explanation + chapter recap** the v1.1 AI anchor. Ship it as an optional “On-device intelligence” setting, isolated behind macOS 26 availability. In parallel, add non-private metadata/annotation Spotlight indexing and a small set of App Intents. That gives Varq useful intelligence on eligible Macs without turning it into a cloud-dependent chat product, while establishing the data and navigation seams needed for trustworthy chapter Q&A later.
