import SwiftUI

struct ReaderAppearanceControls: View {
    let appearance: ReadingAppearance
    let setFontFamily: (ReadingFontFamily) -> Void
    let setFontSize: (Double) -> Void
    let setLineHeight: (Double) -> Void
    let setHorizontalMargin: (Double) -> Void

    var body: some View {
        Menu("Appearance", systemImage: "textformat") {
            Picker("Font", selection: fontFamily) {
                ForEach(ReadingFontFamily.allCases, id: \.self) { fontFamily in
                    Text(fontFamily.displayName).tag(fontFamily)
                }
            }

            Stepper("Font size: \(Int(appearance.fontSize)) pt", value: fontSize, in: fontSizeRange, step: ReadingAppearance.fontSizeStep)

            Picker("Line height", selection: lineHeight) {
                ForEach(ReadingAppearance.lineHeights, id: \.self) { lineHeight in
                    Text("\(lineHeight, format: .number.precision(.fractionLength(1)))").tag(lineHeight)
                }
            }

            Stepper("Margins: \(Int(appearance.horizontalMargin)) pt", value: horizontalMargin, in: horizontalMarginRange, step: ReadingAppearance.horizontalMarginStep)
        }
    }

    private var fontFamily: Binding<ReadingFontFamily> {
        Binding(get: { appearance.fontFamily }, set: setFontFamily)
    }

    private var fontSize: Binding<Double> {
        Binding(get: { appearance.fontSize }, set: setFontSize)
    }

    private var lineHeight: Binding<Double> {
        Binding(get: { appearance.lineHeight }, set: setLineHeight)
    }

    private var horizontalMargin: Binding<Double> {
        Binding(get: { appearance.horizontalMargin }, set: setHorizontalMargin)
    }

    private var fontSizeRange: ClosedRange<Double> {
        ReadingAppearance.minimumFontSize...ReadingAppearance.maximumFontSize
    }

    private var horizontalMarginRange: ClosedRange<Double> {
        ReadingAppearance.minimumHorizontalMargin...ReadingAppearance.maximumHorizontalMargin
    }
}
