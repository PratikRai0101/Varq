import SwiftData
import SwiftUI

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isReaderFocused: Bool
    @State private var viewModel: ReaderViewModel
    @State private var pageTurnDirection: PageTurnDirection = .forward
    @State private var pageTurnProgress: CGFloat = 0
    @State private var readerOpacity = 1.0
    @State private var isTurningPage = false

    init(book: Book, bookURL: URL, renderer: some BookRenderer) {
        _viewModel = State(initialValue: ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer))
    }

    var body: some View {
        ZStack {
            Color.varqIndigo

            NativeRendererView(rendererView: viewModel.rendererView)
                .padding(VarqSpacing.regular)
                .opacity(readerOpacity)

            if !reduceMotion {
                PageTurnOverlay(direction: pageTurnDirection, progress: pageTurnProgress)
            }

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
            performPageTurn(.backward)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            performPageTurn(.forward)
            return .handled
        }
        // WebKit and PDFKit need exclusive drag handling to create text selections.
        // Keyboard navigation remains available while a text renderer is active.
        .simultaneousGesture(
            DragGesture(minimumDistance: VarqLayout.pageTurnSwipeDistance)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    // Require a clearly horizontal, deliberate swipe to avoid
                    // colliding with WebKit text-selection drags.
                    guard abs(horizontal) > abs(vertical) * 2,
                          abs(horizontal) > 80
                    else {
                        return
                    }
                    performPageTurn(horizontal < 0 ? .forward : .backward)
                },
            including: viewModel.supportsTextHighlights ? .none : .all
        )
        .task {
            viewModel.configurePersistence(using: modelContext)
            await viewModel.open()
        }
        .onDisappear { Task { await viewModel.close() } }
        .toolbar {
            if viewModel.supportsTextHighlights {
                ToolbarItem {
                    NavigationLink {
                        HighlightsListView(
                            book: viewModel.highlightedBook,
                            navigateToHighlight: { highlight in
                                Task { await viewModel.navigateToHighlight(highlight) }
                            },
                            deleteHighlight: { highlight in
                                await viewModel.deleteHighlight(highlight)
                            }
                        )
                    } label: {
                        Label("Highlights", systemImage: "list.bullet")
                    }
                }

                ToolbarItem {
                    HighlightCreationControls { color in
                        Task { _ = await viewModel.createHighlight(color: color) }
                    }
                }

                ToolbarItem {
                    Button("Add page note", systemImage: "note.text.badge.plus") {
                        viewModel.beginPageNote()
                    }
                }
            }

            if viewModel.supportsEpubLayoutControls {
                ToolbarItem {
                    EpubLayoutControls(
                        pageLayout: viewModel.readingAppearance.epubPageLayout,
                        setPageLayout: { pageLayout in
                            Task { await viewModel.setEpubPageLayout(pageLayout) }
                        }
                    )
                }
            }

            if viewModel.supportsComicControls {
                ToolbarItem {
                    ComicReadingControls(
                        readingDirection: viewModel.readingAppearance.comicReadingDirection,
                        pageLayout: viewModel.readingAppearance.comicPageLayout,
                        pageFit: viewModel.readingAppearance.comicPageFit,
                        setReadingDirection: { readingDirection in
                            Task { await viewModel.setComicReadingDirection(readingDirection) }
                        },
                        setPageLayout: { pageLayout in
                            Task { await viewModel.setComicPageLayout(pageLayout) }
                        },
                        setPageFit: { pageFit in
                            Task { await viewModel.setComicPageFit(pageFit) }
                        }
                    )
                }
            }

            ToolbarItem {
                ReaderAppearanceControls(
                    appearance: viewModel.readingAppearance,
                    setPageTone: { pageTone in
                        Task { await viewModel.setPageTone(pageTone) }
                    },
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
        .sheet(
            item: Binding(
                get: { viewModel.noteEditorState },
                set: { state in
                    if state == nil {
                        viewModel.cancelNoteEditing()
                    }
                }
            )
        ) { state in
            ReadingNoteEditor(
                state: state,
                saveNote: { body, color in
                    Task { await viewModel.saveNote(body: body, color: color) }
                },
                deleteNote: { note in
                    Task { await viewModel.deleteNote(note) }
                },
                cancel: viewModel.cancelNoteEditing
            )
        }
    }

    private func performPageTurn(_ direction: PageTurnDirection) {
        guard !isTurningPage else {
            return
        }
        isTurningPage = true
        pageTurnDirection = direction

        if reduceMotion {
            withAnimation(.easeInOut(duration: VarqMotion.reducedMotionCrossFadeDuration)) {
                readerOpacity = 0
            }
        } else {
            withAnimation(
                .spring(
                    response: VarqMotion.pageTurnResponse,
                    dampingFraction: VarqMotion.pageTurnDampingFraction
                )
            ) {
                pageTurnProgress = 1
            }
        }

        Task {
            let didNavigate: Bool
            switch direction {
            case .forward:
                didNavigate = await viewModel.goForward()
            case .backward:
                didNavigate = await viewModel.goBackward()
            }

            if reduceMotion {
                withAnimation(.easeInOut(duration: VarqMotion.reducedMotionCrossFadeDuration)) {
                    readerOpacity = 1
                }
            } else {
                withAnimation(
                    .spring(
                        response: VarqMotion.pageTurnResponse,
                        dampingFraction: VarqMotion.pageTurnDampingFraction
                    )
                ) {
                    pageTurnProgress = 0
                }
            }

            if !didNavigate {
                readerOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(VarqMotion.pageTurnSettleMilliseconds))
            isTurningPage = false
        }
    }
}
