import SwiftUI

struct ComicReadingControls: View {
    let readingDirection: ComicReadingDirection
    let pageLayout: ComicPageLayout
    let setReadingDirection: (ComicReadingDirection) -> Void
    let setPageLayout: (ComicPageLayout) -> Void

    var body: some View {
        Menu("Comic layout", systemImage: "rectangle.portrait.arrowtriangle.2.outward") {
            Picker("Reading direction", selection: direction) {
                ForEach(ComicReadingDirection.allCases, id: \.self) { readingDirection in
                    Text(readingDirection.displayName).tag(readingDirection)
                }
            }

            Picker("Page layout", selection: layout) {
                ForEach(ComicPageLayout.allCases, id: \.self) { pageLayout in
                    Text(pageLayout.displayName).tag(pageLayout)
                }
            }
        }
    }

    private var direction: Binding<ComicReadingDirection> {
        Binding(get: { readingDirection }, set: setReadingDirection)
    }

    private var layout: Binding<ComicPageLayout> {
        Binding(get: { pageLayout }, set: setPageLayout)
    }
}
