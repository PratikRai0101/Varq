import AppKit
import SwiftUI

struct BookCoverCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.compact) {
            cover
            progressIndicator

            VStack(alignment: .leading, spacing: VarqSpacing.compact) {
                Text(verbatim: book.title)
                    .font(VarqTypography.uiMedium(.headline))
                    .foregroundStyle(Color.varqInkLight)
                    .lineLimit(2, reservesSpace: true)

                Text(verbatim: book.author)
                    .font(VarqTypography.ui(.subheadline))
                    .foregroundStyle(Color.varqTerracotta)
                    .lineLimit(1, reservesSpace: true)

                Text("\(Int(progressValue * 100))% complete")
                    .font(VarqTypography.ui(.caption))
                    .foregroundStyle(Color.varqSaffron)
                    .lineLimit(1, reservesSpace: true)
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

    private var progressValue: Double {
        min(max(book.readingProgress?.percentComplete ?? 0, 0), 1)
    }

    private var progressIndicator: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.varqIndigo.opacity(0.5))
                Rectangle()
                    .fill(Color.varqSaffron)
                    .frame(width: proxy.size.width * progressValue)
            }
        }
        .frame(height: VarqLayout.bookCardProgressHeight)
        .clipShape(RoundedRectangle(cornerRadius: VarqLayout.bookCardProgressCornerRadius))
        .accessibilityLabel("Reading progress")
        .accessibilityValue("\(Int(progressValue * 100)) percent")
    }

    private var cover: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                if let coverImageData = book.coverImageData,
                   let coverImage = NSImage(data: coverImageData) {
                    Image(nsImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
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
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .aspectRatio(VarqLayout.bookCoverAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.compact))
    }
}
