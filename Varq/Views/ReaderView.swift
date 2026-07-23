import SwiftData
import SwiftUI

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.varqDarkTheme) private var darkTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isReaderFocused: Bool
    @State private var viewModel: ReaderViewModel
    @State private var pageTurnDirection: PageTurnDirection = .forward
    @State private var pageTurnProgress: CGFloat = 0
    @State private var readerOpacity = 1.0
    @State private var isTurningPage = false
    @State private var isHighlightsPresented = false
    @State private var isTableOfContentsPresented = false
    @State private var isAssistantSidebarPresented = false
    private let assistantCompletionService = ReadingAssistantCompletionService()

    init(book: Book, bookURL: URL, renderer: some BookRenderer) {
        _viewModel = State(initialValue: ReaderViewModel(book: book, bookURL: bookURL, renderer: renderer))
    }

    var body: some View {
        ZStack {
            darkTheme.background

            NativeRendererView(rendererView: viewModel.rendererView)
                .padding(VarqSpacing.regular)
                .opacity(readerOpacity)

            if !reduceMotion {
                PageTurnOverlay(direction: pageTurnDirection, progress: pageTurnProgress)
            }

            if isAssistantSidebarPresented {
                assistantSidebar
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
        .sheet(isPresented: $isHighlightsPresented) {
            HighlightsListView(
                book: viewModel.highlightedBook,
                navigateToHighlight: { highlight in
                    Task { await viewModel.navigateToHighlight(highlight) }
                },
                deleteHighlight: { highlight in
                    await viewModel.deleteHighlight(highlight)
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Home", systemImage: "house", action: dismiss.callAsFunction)
                    .accessibilityHint("Return to your library")
            }

            if viewModel.supportsTextHighlights {
                ToolbarItem {
                    Button("Highlights", systemImage: "bookmark") {
                        isHighlightsPresented = true
                    }
                    .help("Browse saved highlights and notes")
                }

                ToolbarItem {
                    HighlightCreationControls { color in
                        Task { _ = await viewModel.createHighlight(color: color) }
                    }
                }

                ToolbarItem {
                    ReadingAssistantControls(
                        availability: viewModel.localIntelligenceAvailability,
                        isGenerating: viewModel.isGeneratingReadingAid,
                        requestAid: { kind in
                            Task { await viewModel.requestReadingAid(kind) }
                        },
                        showUnavailableMessage: viewModel.presentIntelligenceUnavailableMessage
                    )
                }

                ToolbarItem {
                    Button("Show assistant", systemImage: "sidebar.right") {
                        isAssistantSidebarPresented.toggle()
                    }
                    .help("Show or hide the reading assistant")
                }

                ToolbarItem {
                    Button("Add page note", systemImage: "note.text.badge.plus") {
                        viewModel.beginPageNote()
                    }
                    .help("Add a note at this page")
                }
            }

            if viewModel.supportsEpubLayoutControls {
                ToolbarItem {
                    Button("Contents", systemImage: "list.bullet") {
                        Task { await viewModel.loadTableOfContents() }
                        isTableOfContentsPresented = true
                    }
                    .help("Browse the book’s table of contents")
                }

                ToolbarItem {
                    Button("Recap chapter", systemImage: "text.append") {
                        Task { await viewModel.requestChapterRecap() }
                    }
                    .disabled(viewModel.isGeneratingReadingAid)
                    .help("Generate a recap of this chapter")
                }

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
        .onChange(of: viewModel.readingAidInProgress) { _, kind in
            if kind != nil { isAssistantSidebarPresented = true }
        }
        .onChange(of: viewModel.generatedReadingAid) { _, result in
            guard let result else { return }
            isAssistantSidebarPresented = true
            assistantCompletionService.announceCompletion(title: "\(result.kind.displayName) is ready")
        }
        .sheet(isPresented: $isTableOfContentsPresented) {
            TableOfContentsView(
                entries: viewModel.tableOfContents,
                selectEntry: { entry in
                    Task { await viewModel.navigateToTableOfContentsEntry(entry) }
                    isTableOfContentsPresented = false
                }
            )
        }
        .alert(
            "Reading aids unavailable",
            isPresented: intelligenceUnavailableBinding
        ) {
            Button("OK", action: viewModel.dismissIntelligenceUnavailableMessage)
        } message: {
            Text(intelligenceUnavailableMessage)
        }
        .alert(
            "Use local intelligence with this private book?",
            isPresented: privateBookIntelligenceConsentBinding
        ) {
            Button("Not now", role: .cancel, action: viewModel.cancelPrivateBookIntelligenceConsent)
            Button("Continue") {
                Task { await viewModel.grantPrivateBookIntelligenceConsent() }
            }
        } message: {
            Text("Varq will process the selected text on this Mac. This permission applies only to this private book and can be revoked later.")
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

    @ViewBuilder
    private var assistantSidebar: some View {
        Group {
            if let kind = viewModel.readingAidInProgress {
                ReadingAssistantProgressView(kind: kind)
            } else if let result = viewModel.generatedReadingAid {
                GeneratedReadingAidPanel(
                    result: result,
                    saveAsNote: viewModel.saveGeneratedReadingAidAsNote,
                    dismiss: { isAssistantSidebarPresented = false }
                )
            } else {
                ReadingAssistantEmptyView()
            }
        }
        .frame(width: VarqLayout.readingAidPanelWidth)
        .frame(maxHeight: .infinity)
        .background(Color.varqParchment)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(VarqSpacing.regular)
    }

    private var intelligenceUnavailableBinding: Binding<Bool> {
        Binding(
            get: { viewModel.intelligenceUnavailableReason != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissIntelligenceUnavailableMessage()
                }
            }
        )
    }

    private var intelligenceUnavailableMessage: String {
        switch viewModel.intelligenceUnavailableReason {
        case .unsupportedOS:
            "Reading aids require macOS 26 or later."
        case .deviceNotEligible:
            "Reading aids require a Mac that supports Apple Intelligence."
        case .appleIntelligenceDisabled:
            "Turn on Apple Intelligence in System Settings, then reopen Varq."
        case .modelNotReady:
            "Apple Intelligence is still preparing. Try again shortly."
        case .unavailable, nil:
            "Reading aids are unavailable right now."
        }
    }

    private var privateBookIntelligenceConsentBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isPrivateBookIntelligenceConsentPresented },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelPrivateBookIntelligenceConsent()
                }
            }
        )
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
