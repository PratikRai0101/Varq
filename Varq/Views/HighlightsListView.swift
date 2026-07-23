import SwiftUI

struct HighlightsListView: View {
    let book: Book
    var navigateToHighlight: ((Highlight) -> Void)?
    var deleteHighlight: ((Highlight) async -> Bool)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = HighlightsViewModel()

    var body: some View {
        Group {
            if viewModel.highlights.isEmpty {
                highlightEmptyState
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
                                    .font(VarqTypography.ui(.caption))
                                    .foregroundStyle(colorScheme == .dark ? Color.varqSaffron : Color.varqTerracotta)
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
                    .accessibilityHint("Open this highlight in the reader.")
                    .contextMenu {
                        Button("Remove highlight", role: .destructive) {
                            Task {
                                guard let deleteHighlight,
                                      await deleteHighlight(highlight) else {
                                    return
                                }
                                viewModel.remove(highlight)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(VarqSpacing.regular)
        .background(colorScheme == .dark ? Color.varqIndigo : Color.varqParchment)
        .navigationTitle("Highlights")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back to reader", systemImage: "chevron.backward", action: dismiss.callAsFunction)
            }
        }
        .task { viewModel.load(for: book) }
    }

    private var highlightEmptyState: some View {
        VStack(spacing: VarqSpacing.regular) {
            Image(systemName: "highlighter")
                .font(VarqTypography.ui(.largeTitle))
                .foregroundStyle(Color.varqSaffron)
                .accessibilityHidden(true)

            Text("No highlights yet")
                .font(VarqTypography.uiMedium(.title2))
                .foregroundStyle(primaryTextColor)

            Text("Select text in the reader to save a highlight.")
                .font(VarqTypography.ui(.body))
                .foregroundStyle(primaryTextColor.opacity(VarqOpacity.secondaryText))
                .multilineTextAlignment(.center)
        }
        .padding(VarqSpacing.large)
        .frame(maxWidth: VarqLayout.highlightEmptyStateMaximumWidth)
        .background(colorScheme == .dark ? Color.varqIndigoLight : Color.varqParchmentDeep)
        .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.compact))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.varqInkDark : Color.varqInkLight
    }

    private func color(for colorTag: String) -> Color {
        HighlightColorTag(rawValue: colorTag)?.varqColor ?? Color.varqSaffron
    }
}
