import SwiftUI

struct ComicReadingControls: View {
    let readingDirection: ComicReadingDirection
    let setReadingDirection: (ComicReadingDirection) -> Void

    var body: some View {
        Menu("Comic layout", systemImage: "rectangle.portrait.arrowtriangle.2.outward") {
            Picker("Reading direction", selection: direction) {
                ForEach(ComicReadingDirection.allCases, id: \.self) { readingDirection in
                    Text(readingDirection.displayName).tag(readingDirection)
                }
            }
        }
    }

    private var direction: Binding<ComicReadingDirection> {
        Binding(get: { readingDirection }, set: setReadingDirection)
    }
}
