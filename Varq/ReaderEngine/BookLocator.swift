import Foundation

struct BookLocator: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let format: BookFormat
    let spineIndex: Int
    let resourceHref: String?
    let progression: Double

    init(
        schemaVersion: Int = BookLocator.currentSchemaVersion,
        format: BookFormat,
        spineIndex: Int,
        resourceHref: String? = nil,
        progression: Double
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw BookLocatorError.unsupportedSchemaVersion(schemaVersion)
        }
        guard spineIndex >= 0 else {
            throw BookLocatorError.negativeSpineIndex
        }
        guard progression.isFinite, (0...1).contains(progression) else {
            throw BookLocatorError.invalidProgression(progression)
        }
        if format == .epub, resourceHref?.isEmpty != false {
            throw BookLocatorError.missingEpubResourceHref
        }

        self.schemaVersion = schemaVersion
        self.format = format
        self.spineIndex = spineIndex
        self.resourceHref = resourceHref
        self.progression = progression
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case format
        case spineIndex
        case resourceHref
        case progression
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            format: container.decode(BookFormat.self, forKey: .format),
            spineIndex: container.decode(Int.self, forKey: .spineIndex),
            resourceHref: container.decodeIfPresent(String.self, forKey: .resourceHref),
            progression: container.decode(Double.self, forKey: .progression)
        )
    }
}

enum BookLocatorError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case negativeSpineIndex
    case invalidProgression(Double)
    case missingEpubResourceHref
}
