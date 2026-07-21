import Foundation

/// A versioned, renderer-neutral text range persisted in `Highlight.locatorData`.
/// Offsets are UTF-16 offsets in the text content unit identified by `locator`.
struct TextHighlightAnchor: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let locator: BookLocator
    let startOffset: Int
    let endOffset: Int
    let quote: TextQuoteSelector

    init(
        schemaVersion: Int = TextHighlightAnchor.currentSchemaVersion,
        locator: BookLocator,
        startOffset: Int,
        endOffset: Int,
        quote: TextQuoteSelector
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TextHighlightAnchorError.unsupportedSchemaVersion(schemaVersion)
        }
        guard locator.format == .epub || locator.format == .pdf else {
            throw TextHighlightAnchorError.unsupportedFormat(locator.format)
        }
        guard startOffset >= 0, endOffset > startOffset else {
            throw TextHighlightAnchorError.invalidTextRange(start: startOffset, end: endOffset)
        }
        guard !quote.exact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextHighlightAnchorError.emptyQuote
        }

        self.schemaVersion = schemaVersion
        self.locator = locator
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.quote = quote
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case locator
        case startOffset
        case endOffset
        case quote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            locator: container.decode(BookLocator.self, forKey: .locator),
            startOffset: container.decode(Int.self, forKey: .startOffset),
            endOffset: container.decode(Int.self, forKey: .endOffset),
            quote: container.decode(TextQuoteSelector.self, forKey: .quote)
        )
    }
}

struct TextQuoteSelector: Codable, Equatable, Sendable {
    let exact: String
    let prefix: String?
    let suffix: String?

    init(exact: String, prefix: String? = nil, suffix: String? = nil) {
        self.exact = exact
        self.prefix = prefix
        self.suffix = suffix
    }
}

enum TextHighlightAnchorError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case unsupportedFormat(BookFormat)
    case invalidTextRange(start: Int, end: Int)
    case emptyQuote
}
