# Varq Reading

The language used to describe how Varq opens books and preserves a reader's place across supported formats.

## Language

**Reader engine**:
The native macOS components that open and render a book in its specific format.
_Avoid_: Readium integration, renderer

**Reading locator**:
A serializable, format-specific record of a reader's position in a book.
_Avoid_: page position, CFI
