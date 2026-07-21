import AppKit
import SwiftUI

struct BookCoverCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.compact) {
            cover
                .aspectRatio(0.68, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.compact))

            Text(book.title)
                .font(VarqTypography.uiMedium(.headline))
                .foregroundStyle(Color.varqInkLight)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(book.author)
                .font(VarqTypography.ui(.subheadline))
                .foregroundStyle(Color.varqTerracotta)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title) by \(book.author)")
    }

    @ViewBuilder
    private var cover: some View {
        if let coverImageData = book.coverImageData,
           let coverImage = NSImage(data: coverImageData) {
            Image(nsImage: coverImage)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: VarqSpacing.compact)
                .fill(Color.varqIndigo)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(VarqTypography.ui(.largeTitle))
                        .foregroundStyle(Color.varqSaffron)
                }
        }
    }
}
