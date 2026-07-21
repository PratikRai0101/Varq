import AppKit
import SwiftUI

struct BookCoverCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.compact) {
            cover
                .frame(maxWidth: .infinity)
                .aspectRatio(0.68, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.compact))

            if let progress = book.readingProgress, progress.percentComplete > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.varqIndigo.opacity(0.5))
                        Rectangle()
                            .fill(Color.varqSaffron)
                            .frame(width: proxy.size.width * CGFloat(progress.percentComplete))
                    }
                }
                .frame(height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            VStack(alignment: .leading, spacing: VarqSpacing.compact) {
                Text(verbatim: book.title)
                    .font(VarqTypography.uiMedium(.headline))
                    .foregroundStyle(Color.varqInkLight)
                    .lineLimit(2)

                Text(verbatim: book.author)
                    .font(VarqTypography.ui(.subheadline))
                    .foregroundStyle(Color.varqTerracotta)
                    .lineLimit(1)
            }
            // Pad both edges so glyph overhang stays inside the card bounds.
            .padding(.horizontal, VarqSpacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, VarqSpacing.compact)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title) by \(book.author)")
    }

    @ViewBuilder
    private var cover: some View {
        ZStack(alignment: .topTrailing) {
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

            if book.isPrivate {
                Image(systemName: "lock.fill")
                    .font(VarqTypography.ui(.caption))
                    .foregroundStyle(Color.varqSaffron)
                    .padding(VarqSpacing.compact)
                    .background(Color.varqIndigo.opacity(0.72))
                    .clipShape(Circle())
                    .padding(VarqSpacing.compact)
            }
        }
    }
}
