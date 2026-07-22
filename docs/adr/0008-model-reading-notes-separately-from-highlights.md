# Model reading notes separately from highlights

**Status:** Accepted

## Context

A text highlight and a personal note answer different reader needs. A highlight is a colored treatment of selected text. A note is authored content that should have a citation-like marker, a hover summary, and a dedicated editor. Combining them in `Highlight.note` made note markers and page-level notes impossible to model cleanly.

EPUB physical pages reflow with typography and window changes, so a page note cannot use a permanent printed page number.

## Decision

Introduce the `ReadingNote` SwiftData model and the versioned `ReadingNoteAnchor` value:

- a text-selection note embeds a `TextHighlightAnchor`;
- a page note stores the current `BookLocator`.

Each note has its own body, color tag, created/modified dates, and `Book` relationship. Readers render a small colored note marker at the selected text or current location. Hovering exposes a summary; activating the marker opens the editor.

New note creation uses a text renderer's contextual menu (`Add note…`) or `Add page note…`. `Highlight.note` remains only as a legacy persistence field for existing libraries; new UI and behavior use `ReadingNote`.

## Consequences

- Highlights and notes can evolve independently and be exported as separate collections.
- Page notes are stable at the level of an EPUB spine resource and normalized reading progression, not a fixed visual page number.
- The reader-engine seam owns marker placement and activation while `ReaderViewModel` owns persistence and editor state.
