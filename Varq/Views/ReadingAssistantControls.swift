import SwiftUI

struct ReadingAssistantControls: View {
    let availability: AIAssistantAvailability
    let isGenerating: Bool
    let requestAid: (ReadingAidKind) -> Void

    var body: some View {
        Menu("Reading aids", systemImage: "sparkles") {
            ForEach(aidKinds, id: \.self) { kind in
                Button(kind.displayName) {
                    requestAid(kind)
                }
            }
        }
        .disabled(isGenerating || !isAvailable)
        .accessibilityHint(accessibilityHint)
        .overlay {
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Generating reading aid")
            }
        }
    }

    private var isAvailable: Bool {
        if case .available = availability {
            return true
        }
        return false
    }

    private var aidKinds: [ReadingAidKind] {
        [.explain, .simplify, .summarize, .discussionQuestions]
    }

    private var accessibilityHint: String {
        switch availability {
        case .available:
            "Select text in the reader, then choose a reading aid."
        case .unavailable:
            "This Mac cannot use local reading aids right now."
        }
    }
}

struct GeneratedReadingAidView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.varqDarkTheme) private var darkTheme

    let result: GeneratedReadingAidResult
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.regular) {
            Text(result.kind.displayName)
                .font(VarqTypography.uiMedium(.title2))
                .foregroundStyle(primaryTextColor)

            ScrollView {
                Text(result.text)
                    .font(VarqTypography.ui(.body))
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(VarqSpacing.regular)
            .background(surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.compact))

            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VarqSpacing.large)
        .frame(
            minWidth: VarqLayout.noteEditorMinimumWidth,
            minHeight: VarqLayout.noteEditorMinimumHeight
        )
        .background(backgroundColor)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? darkTheme.background : Color.varqParchment
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? darkTheme.surface : Color.varqParchmentDeep
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? darkTheme.primaryText : Color.varqInkLight
    }
}
