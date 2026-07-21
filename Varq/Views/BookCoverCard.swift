import AppKit
import SwiftUI

struct BookCoverCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.compact) {
            cover
                .aspectRatio(0.68, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.compact))

            VStack(alignment: .leading, spacing: VarqSpacing.compact) {
                Text(verbatim: book.title)
                    .font(VarqTypography.uiMedium(.headline))
                    .foregroundStyle(Color.varqInkLight)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: book.author)
                    .font(VarqTypography.ui(.subheadline))
                    .foregroundStyle(Color.varqTerracotta)
                    .lineLimit(1)
            }
            // Keep glyph overhang inside the card; long metadata must never be clipped at its leading edge.
            .padding(.horizontal, VarqSpacing.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, VarqSpacing.compact)
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
