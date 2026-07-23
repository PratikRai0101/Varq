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

**Reading Artifact**:
A user-owned Text Highlight or Reading Note associated with a book.

**Private Book**:
A book whose managed library file is encrypted at rest and requires system authentication to open. Private is a protection promise, not merely a library filter.

**Generated Reading Aid**:
An explicitly requested, non-authoritative response about book content, such as an explanation, summary, or discussion question. It is not a Reading Artifact until the reader explicitly saves it as one.
_Avoid_: note, highlight

**Local Intelligence**:
A Generated Reading Aid produced entirely on the person’s device. It never transfers book content off the device.

**Private Cloud Intelligence**:
An opt-in Generated Reading Aid produced using Apple Private Cloud Compute. It is distinct from Local Intelligence because it sends the request to Apple’s Private Cloud Compute service.

**Search Index**:
A device-local, searchable representation of selected Varq content for Spotlight and grounded retrieval. It has an explicit scope and excludes Private Books by default.

**Vault Export**:
A user-initiated export of Varq’s book and Reading Artifact data into a folder chosen by the person. An Obsidian Vault Export uses stable Markdown files and wikilinks so Obsidian can build its local graph.
