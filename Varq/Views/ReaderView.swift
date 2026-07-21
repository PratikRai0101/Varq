import SwiftUI

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isReaderFocused: Bool
    @State private var viewModel: ReaderViewModel

    init(bookURL: URL, renderer: some BookRenderer) {
        _viewModel = State(initialValue: ReaderViewModel(bookURL: bookURL, renderer: renderer))
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
        .task { await viewModel.open() }
        .onDisappear { Task { await viewModel.close() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Close reader", systemImage: "xmark", action: dismiss.callAsFunction)
            }
        }
    }
}
