# Varq Reading

The language used to describe how Varq opens books and preserves a reader's place across supported formats.

## Language

**Reader engine**:
The native macOS components that open and render a book in its specific format.
_Avoid_: Readium integration, renderer

**Reading locator**:
A serializable, format-specific record of a reader's position in a book.
_Avoid_: page position, CFI

**Managed library file**:
Varq's private copy of an imported book, identified by a relative path within its managed library.
_Avoid_: book file bookmark, external file URL

**Text highlight**:
A colored, persistent visual annotation of a selected passage. It has a text anchor and color, but no personal-note body.
_Avoid_: note, citation

**Reading note**:
A personal annotation attached either to a selected passage or to the current reflow-aware reader location. A note is rendered as a colored citation marker that opens its body.
_Avoid_: colored highlight, comment bubble

**Note marker**:
The small, clickable citation-like affordance rendered beside a reading note's target. Its hover text is a summary of the note body.
_Avoid_: highlight
