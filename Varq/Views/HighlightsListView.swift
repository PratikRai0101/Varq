import SwiftUI

struct HighlightsListView: View {
    let book: Book
    var navigateToHighlight: ((Highlight) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = HighlightsViewModel()

    var body: some View {
        Group {
            if viewModel.highlights.isEmpty {
                ContentUnavailableView("No highlights yet", systemImage: "highlighter", description: Text("Select EPUB text in the reader to save a highlight."))
            } else {
                List(viewModel.highlights, id: \.id) { highlight in
                    Button {
                        navigateToHighlight?(highlight)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: VarqSpacing.compact) {
                            HStack {
                                Circle()
                                    .fill(color(for: highlight.colorTag))
                                    .frame(width: VarqSpacing.compact, height: VarqSpacing.compact)
                                Text(highlight.selectedText)
                                    .font(VarqTypography.reading())
                                    .foregroundStyle(colorScheme == .dark ? Color.varqInkDark : Color.varqInkLight)
                                Spacer()
                                Image(systemName: "arrow.forward")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let note = highlight.note {
                                Text(note)
                                    .font(VarqTypography.ui(.body))
                                    .foregroundStyle(colorScheme == .dark ? Color.varqInkDark : Color.varqInkLight)
                            }
                        }
                        .padding(.vertical, VarqSpacing.compact)
                    }
                    .buttonStyle(.plain)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(VarqSpacing.regular)
        .background(colorScheme == .dark ? Color.varqIndigo : Color.varqParchment)
        .navigationTitle("Highlights")
        .task { viewModel.load(for: book) }
    }

    private func color(for colorTag: String) -> Color {
        switch HighlightColorTag(rawValue: colorTag) {
        case .saffron: Color.varqSaffron
        case .terracotta: Color.varqTerracotta
        case .maroon: Color.varqMaroon
        case nil: Color.varqSaffron
        }
    }
}
