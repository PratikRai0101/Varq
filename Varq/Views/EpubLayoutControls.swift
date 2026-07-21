import SwiftUI

struct EpubLayoutControls: View {
    let pageLayout: EpubPageLayout
    let setPageLayout: (EpubPageLayout) -> Void

    var body: some View {
        Menu("Page layout", systemImage: "rectangle.split.2x1") {
            Picker("Page layout", selection: layout) {
                ForEach(EpubPageLayout.allCases, id: \.self) { pageLayout in
                    Text(pageLayout.displayName).tag(pageLayout)
                }
            }
        }
    }

    private var layout: Binding<EpubPageLayout> {
        Binding(get: { pageLayout }, set: setPageLayout)
    }
}
