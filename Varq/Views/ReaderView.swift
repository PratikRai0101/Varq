import SwiftData
import SwiftUI

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isReaderFocused: Bool
    @State private var viewModel: ReaderViewModel

    init(book: Book, bookURL: URL, renderer: some BookRenderer) {
        _viewModel = State(initialValue: ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer))
    }

    var body: some View {
        ZStack {
            Color.varqIndigo

            NativeRendererView(rendererView: viewModel.rendererView)
                .padding(VarqSpacing.regular)

            if let errorMessage = viewModel.errorMessage {
                VStack {
                    Text(errorMessage)
                        .font(VarqTypography.ui(.body))
                        .foregroundStyle(Color.varqInkDark)
                        .padding(VarqSpacing.regular)
                        .background(Color.varqMaroon)
                    Spacer()
                }
            }
        }
        .focusable()
        .focused($isReaderFocused)
        .onAppear { isReaderFocused = true }
        .onKeyPress(.leftArrow) {
            Task { await viewModel.goBackward() }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            Task { await viewModel.goForward() }
            return .handled
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: VarqLayout.pageTurnSwipeDistance)
                .onEnded { value in
                    Task {
                        if value.translation.width < 0 {
                            await viewModel.goForward()
                        } else {
                            await viewModel.goBackward()
                        }
                    }
                }
        )
        .task {
            viewModel.configurePersistence(using: modelContext)
            await viewModel.open()
        }
        .onDisappear { Task { await viewModel.close() } }
        .toolbar {
            ToolbarItem {
                ReaderAppearanceControls(
                    appearance: viewModel.readingAppearance,
                    setFontFamily: { fontFamily in
                        Task { await viewModel.setFontFamily(fontFamily) }
                    },
                    setFontSize: { fontSize in
                        Task { await viewModel.setFontSize(fontSize) }
                    },
                    setLineHeight: { lineHeight in
                        Task { await viewModel.setLineHeight(lineHeight) }
                    },
                    setHorizontalMargin: { horizontalMargin in
                        Task { await viewModel.setHorizontalMargin(horizontalMargin) }
                    }
                )
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Close reader", systemImage: "xmark", action: dismiss.callAsFunction)
            }
        }
    }
}
