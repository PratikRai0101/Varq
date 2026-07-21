import Foundation
import Testing
@testable import Varq

struct BookLocatorTests {
    @Test func roundTripsAnEpubLocation() throws {
        let locator = try BookLocator(
            format: .epub,
            spineIndex: 2,
            resourceHref: "text/chapter-3.xhtml",
            progression: 0.375
        )

        let encoded = try JSONEncoder().encode(locator)
        let decoded = try JSONDecoder().decode(BookLocator.self, from: encoded)

        #expect(decoded == locator)
        #expect(decoded.schemaVersion == BookLocator.currentSchemaVersion)
    }

    @Test(arguments: [-0.1, 1.1, .infinity])
    func rejectsInvalidProgression(_ progression: Double) {
        #expect(throws: BookLocatorError.invalidProgression(progression)) {
            try BookLocator(
                format: .epub,
                spineIndex: 0,
                resourceHref: "chapter.xhtml",
                progression: progression
            )
        }
    }

    @Test func rejectsAnEpubLocationWithoutAResourceHref() {
        #expect(throws: BookLocatorError.missingEpubResourceHref) {
            try BookLocator(format: .epub, spineIndex: 0, progression: 0)
        }
    }
}
