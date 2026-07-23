import AppKit
import SwiftUI

struct ReadingAssistantControls: View {
    let availability: AIAssistantAvailability
    let isGenerating: Bool
    let requestAid: (ReadingAidKind) -> Void
    let showUnavailableMessage: () -> Void

    var body: some View {
        Group {
            if isAvailable {
                Menu("Reading aids", systemImage: "sparkles") {
                    ForEach(aidKinds, id: \.self) { kind in
                        Button(kind.displayName) {
                            requestAid(kind)
                        }
                    }
                }
                .disabled(isGenerating)
            } else {
                Button("Reading aids unavailable", systemImage: "sparkles", action: showUnavailableMessage)
            }
        }
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

struct GeneratedReadingAidPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.varqDarkTheme) private var darkTheme

    let result: GeneratedReadingAidResult
    let saveAsNote: () -> Void
    let dismiss: () -> Void

    @State private var hasCopiedResponse = false

    var body: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.regular) {
            HStack(alignment: .firstTextBaseline, spacing: VarqSpacing.compact) {
                Image(systemName: "sparkles")
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VarqSpacing.compact) {
                    Text(result.kind.displayName)
                        .font(VarqTypography.uiMedium(.headline))
                        .foregroundStyle(primaryTextColor)
                    Text("On-device response about your selection")
                        .font(VarqTypography.ui(.caption))
                        .foregroundStyle(primaryTextColor.opacity(VarqOpacity.secondaryText))
                }

                Spacer()

                Button("Close", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Close reading aid")
            }

            ScrollView {
                Text(plainText)
                    .font(VarqTypography.ui(.body))
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(VarqSpacing.regular)
            .background(surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.compact))

            HStack {
                Button(copyButtonTitle, systemImage: copyButtonSymbol, action: copyResponse)
                    .buttonStyle(.bordered)

                Button("Save as note", systemImage: "note.text.badge.plus", action: saveAsNote)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Done", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VarqSpacing.large)
        .frame(width: VarqLayout.readingAidPanelWidth)
        .frame(minHeight: VarqLayout.readingAidPanelMinimumHeight)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.regular))
        .overlay {
            RoundedRectangle(cornerRadius: VarqSpacing.regular)
                .stroke(accentColor.opacity(VarqOpacity.settingsTabBorder))
        }
        .accessibilityElement(children: .contain)
    }

    private var copyButtonTitle: String {
        hasCopiedResponse ? "Copied" : "Copy"
    }

    private var copyButtonSymbol: String {
        hasCopiedResponse ? "checkmark" : "doc.on.doc"
    }

    private func copyResponse() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
        hasCopiedResponse = true
    }

    private var plainText: String {
        result.text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
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

    private var accentColor: Color {
        colorScheme == .dark ? darkTheme.accent : Color.varqSaffron
    }
}
