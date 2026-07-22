import Foundation

/// A versioned anchor for a personal note attached to either selected text or a reader location.
struct ReadingNoteAnchor: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let kind: ReadingNoteAnchorKind
    let locator: BookLocator
    let textSelection: TextHighlightAnchor?

    init(textSelection: TextHighlightAnchor) {
        schemaVersion = Self.currentSchemaVersion
        kind = .textSelection
        locator = textSelection.locator
        self.textSelection = textSelection
    }

    init(pageLocator: BookLocator) {
        schemaVersion = Self.currentSchemaVersion
        kind = .pageLocation
        locator = pageLocator
        textSelection = nil
    }

    var selectedText: String? {
        textSelection?.quote.exact
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, locator, textSelection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ReadingNoteAnchorError.unsupportedSchemaVersion(schemaVersion)
        }

        let kind = try container.decode(ReadingNoteAnchorKind.self, forKey: .kind)
        let locator = try container.decode(BookLocator.self, forKey: .locator)
        let textSelection = try container.decodeIfPresent(TextHighlightAnchor.self, forKey: .textSelection)
        switch kind {
        case .textSelection:
            guard let textSelection, textSelection.locator == locator else {
                throw ReadingNoteAnchorError.invalidTextSelection
            }
        case .pageLocation:
            guard textSelection == nil else {
                throw ReadingNoteAnchorError.invalidPageLocation
            }
        }

        self.schemaVersion = schemaVersion
        self.kind = kind
        self.locator = locator
        self.textSelection = textSelection
    }
}

enum ReadingNoteAnchorKind: String, Codable, Equatable, Sendable {
    case textSelection
    case pageLocation
}

enum ReadingNoteAnchorError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidTextSelection
    case invalidPageLocation
}
