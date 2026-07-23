import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.varqDarkTheme) private var darkTheme
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel
    @State private var isRestoreDefaultsConfirmationPresented = false

    init() {
        _viewModel = State(initialValue: SettingsViewModel())
    }

    var body: some View {
        VStack(spacing: VarqSpacing.large) {
            settingsHeader
            SettingsTabPicker(selectedTab: $viewModel.selectedTab)

            ScrollView {
                selectedTabContent
                    .frame(maxWidth: VarqLayout.settingsContentMaximumWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, VarqSpacing.regular)
            }

        }
        .padding(VarqSpacing.large)
        .frame(width: VarqLayout.settingsWindowWidth, height: VarqLayout.settingsWindowHeight)
        .background(backgroundColor)
        .tint(colorScheme == .dark ? darkTheme.accent : Color.varqSaffron)
        .alert("Restore default settings?", isPresented: $isRestoreDefaultsConfirmationPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Restore defaults", role: .destructive) {
                viewModel.restoreDefaults()
            }
        } message: {
            Text("This restores the appearance, library display, and new-reader defaults. It does not change your books, highlights, or notes.")
        }
    }

    private var settingsHeader: some View {
        HStack {
            Spacer()
            Button("Done", action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)
        }
        .overlay {
            Text(viewModel.selectedTab.title)
                .font(VarqTypography.uiMedium(.title2))
                .foregroundStyle(primaryTextColor)
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch viewModel.selectedTab {
        case .general:
            generalSettings
        case .reading:
            readingSettings
        case .library:
            librarySettings
        case .advanced:
            advancedSettings
        }
    }

    private var generalSettings: some View {
        VStack(spacing: VarqSpacing.large) {
            SettingsSection("Appearance") {
                SettingsRow(
                    title: "App appearance",
                    detail: "Choose a light, indigo, black, monochrome, or system-matched interface."
                ) {
                    Picker("App appearance", selection: appearanceBinding) {
                        ForEach(AppAppearance.allCases, id: \.self) { appearance in
                            Text(appearance.displayName).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("App appearance")
                }
            }

            SettingsSection("Reading defaults") {
                SettingsRow(
                    title: "New readers",
                    detail: "Choose the page style used when you open a book. You can always change it from the reader toolbar."
                ) {
                    Button("Adjust reading defaults") {
                        viewModel.selectedTab = .reading
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var readingSettings: some View {
        VStack(spacing: VarqSpacing.large) {
            SettingsSection("Text books") {
                SettingsRow(
                    title: "Page tone",
                    detail: "The default background for EPUB and PDF pages."
                ) {
                    Picker("Page tone", selection: readingBinding(\.pageTone)) {
                        ForEach(ReaderPageTone.allCases, id: \.self) { pageTone in
                            Text(pageTone.displayName).tag(pageTone)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("Default page tone")
                }

                SettingsDivider()

                SettingsRow(
                    title: "Font",
                    detail: "The serif family used for new EPUB readers."
                ) {
                    Picker("Font", selection: readingBinding(\.fontFamily)) {
                        ForEach(ReadingFontFamily.allCases, id: \.self) { fontFamily in
                            Text(fontFamily.displayName).tag(fontFamily)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("Default reading font")
                }

                SettingsDivider()

                SettingsRow(
                    title: "Text size",
                    detail: "The default type size for new EPUB readers."
                ) {
                    Stepper(
                        "\(Int(viewModel.settings.defaultReadingAppearance.fontSize)) pt",
                        value: readingBinding(\.fontSize),
                        in: ReadingAppearance.minimumFontSize...ReadingAppearance.maximumFontSize,
                        step: ReadingAppearance.fontSizeStep
                    )
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("Default text size")
                }

                SettingsDivider()

                SettingsRow(
                    title: "Line height",
                    detail: "The default spacing between lines in new EPUB readers."
                ) {
                    Picker("Line height", selection: readingBinding(\.lineHeight)) {
                        ForEach(ReadingAppearance.lineHeights, id: \.self) { lineHeight in
                            Text("\(lineHeight, format: .number.precision(.fractionLength(1)))").tag(lineHeight)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("Default line height")
                }

                SettingsDivider()

                SettingsRow(
                    title: "Page margins",
                    detail: "The horizontal margin for new EPUB readers."
                ) {
                    Stepper(
                        "\(Int(viewModel.settings.defaultReadingAppearance.horizontalMargin)) pt",
                        value: readingBinding(\.horizontalMargin),
                        in: ReadingAppearance.minimumHorizontalMargin...ReadingAppearance.maximumHorizontalMargin,
                        step: ReadingAppearance.horizontalMarginStep
                    )
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("Default page margins")
                }

                SettingsDivider()

                SettingsRow(
                    title: "EPUB layout",
                    detail: "Use a single page or a two-page spread by default."
                ) {
                    Picker("EPUB layout", selection: readingBinding(\.epubPageLayout)) {
                        ForEach(EpubPageLayout.allCases, id: \.self) { pageLayout in
                            Text(pageLayout.displayName).tag(pageLayout)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("Default EPUB layout")
                }
            }

            SettingsSection("Comics") {
                SettingsRow(
                    title: "Reading direction",
                    detail: "Set the default direction for CBZ comics and manga."
                ) {
                    Picker("Comic reading direction", selection: readingBinding(\.comicReadingDirection)) {
                        ForEach(ComicReadingDirection.allCases, id: \.self) { readingDirection in
                            Text(readingDirection.displayName).tag(readingDirection)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("Default comic reading direction")
                }

                SettingsDivider()

                SettingsRow(
                    title: "Page layout",
                    detail: "Choose single pages or two-page spreads by default."
                ) {
                    Picker("Comic page layout", selection: readingBinding(\.comicPageLayout)) {
                        ForEach(ComicPageLayout.allCases, id: \.self) { pageLayout in
                            Text(pageLayout.displayName).tag(pageLayout)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("Default comic page layout")
                }

                SettingsDivider()

                SettingsRow(
                    title: "Page fit",
                    detail: "Choose how comic pages fit in a new reader."
                ) {
                    Picker("Comic page fit", selection: readingBinding(\.comicPageFit)) {
                        ForEach(ComicPageFit.allCases, id: \.self) { pageFit in
                            Text(pageFit.displayName).tag(pageFit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: VarqLayout.settingsControlMaximumWidth)
                    .accessibilityLabel("Default comic page fit")
                }
            }
        }
    }

    private var librarySettings: some View {
        VStack(spacing: VarqSpacing.large) {
            SettingsSection("Book cards") {
                SettingsRow(
                    title: "Show reading progress",
                    detail: "Display each started book's completion percentage in the library."
                ) {
                    Toggle("Show reading progress", isOn: showsReadingProgressBinding)
                        .labelsHidden()
                        .accessibilityLabel("Show reading progress")
                }

                SettingsDivider()

                SettingsRow(
                    title: "Show private-book badges",
                    detail: "Display a lock badge on books protected by Touch ID."
                ) {
                    Toggle("Show private-book badges", isOn: showsPrivateBookBadgesBinding)
                        .labelsHidden()
                        .accessibilityLabel("Show private-book badges")
                }
            }
        }
    }

    private var advancedSettings: some View {
        VStack(spacing: VarqSpacing.large) {
            SettingsSection("Defaults") {
                SettingsRow(
                    title: "Restore default settings",
                    detail: "Restore the original appearance, library display, and new-reader defaults."
                ) {
                    Button("Restore defaults", role: .destructive) {
                        isRestoreDefaultsConfirmationPresented = true
                    }
                    .buttonStyle(.bordered)
                    .tint(colorScheme == .dark ? darkTheme.destructiveAccent : Color.varqMaroon)
                }
            }

            SettingsSection("About Varq") {
                SettingsRow(
                    title: "Native macOS reader",
                    detail: "Varq supports EPUB, PDF, and CBZ files. Your library, highlights, and notes stay on this Mac."
                ) {
                    EmptyView()
                }
            }
        }
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { viewModel.settings.appearance },
            set: viewModel.setAppearance
        )
    }

    private var showsReadingProgressBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.showsReadingProgress },
            set: viewModel.setShowsReadingProgress
        )
    }

    private var showsPrivateBookBadgesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.showsPrivateBookBadges },
            set: viewModel.setShowsPrivateBookBadges
        )
    }

    private func readingBinding<Value>(_ keyPath: WritableKeyPath<ReadingAppearance, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.settings.defaultReadingAppearance[keyPath: keyPath] },
            set: { value in
                var readingAppearance = viewModel.settings.defaultReadingAppearance
                readingAppearance[keyPath: keyPath] = value
                viewModel.setDefaultReadingAppearance(readingAppearance)
            }
        )
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? darkTheme.background : Color.varqParchment
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? darkTheme.primaryText : Color.varqInkLight
    }
}

private struct SettingsTabPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.varqDarkTheme) private var darkTheme
    @Binding var selectedTab: SettingsViewModel.Tab

    var body: some View {
        HStack(spacing: VarqSpacing.regular) {
            ForEach(SettingsViewModel.Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: VarqSpacing.compact) {
                        Image(systemName: tab.symbolName)
                            .font(VarqTypography.ui(.title2))
                        Text(tab.title)
                            .font(VarqTypography.uiMedium(.subheadline))
                    }
                    .frame(width: VarqLayout.settingsTabWidth, height: VarqLayout.settingsTabHeight)
                    .foregroundStyle(tab == selectedTab ? primaryTextColor : secondaryTextColor)
                    .background {
                        RoundedRectangle(cornerRadius: VarqSpacing.compact)
                            .fill(tab == selectedTab ? selectedBackgroundColor : Color.clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: VarqSpacing.compact)
                            .stroke(tab == selectedTab ? (colorScheme == .dark ? darkTheme.accent : Color.varqSaffron).opacity(VarqOpacity.settingsTabBorder) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selectedTab ? .isSelected : [])
            }
        }
    }

    private var selectedBackgroundColor: Color {
        colorScheme == .dark ? darkTheme.surface : Color.varqParchmentDeep
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? darkTheme.primaryText : Color.varqInkLight
    }

    private var secondaryTextColor: Color {
        primaryTextColor.opacity(VarqOpacity.settingsSecondaryText)
    }
}

private struct SettingsSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.varqDarkTheme) private var darkTheme

    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VarqSpacing.compact) {
            Text(title)
                .font(VarqTypography.uiMedium(.headline))
                .foregroundStyle(primaryTextColor)

            VStack(spacing: 0) {
                content
            }
            .background(surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.compact))
        }
    }

    private var surfaceColor: Color {
        colorScheme == .dark ? darkTheme.surface : Color.varqParchmentDeep
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? darkTheme.primaryText : Color.varqInkLight
    }
}

private struct SettingsRow<Control: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.varqDarkTheme) private var darkTheme

    let title: String
    let detail: String
    @ViewBuilder let control: Control

    init(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: VarqSpacing.regular) {
            VStack(alignment: .leading, spacing: VarqSpacing.compact) {
                Text(title)
                    .font(VarqTypography.uiMedium(.body))
                    .foregroundStyle(primaryTextColor)

                Text(detail)
                    .font(VarqTypography.ui(.caption))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: VarqSpacing.regular)

            control
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(VarqSpacing.regular)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? darkTheme.primaryText : Color.varqInkLight
    }

    private var secondaryTextColor: Color {
        primaryTextColor.opacity(VarqOpacity.settingsSecondaryText)
    }
}

private struct SettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.varqDarkTheme) private var darkTheme

    var body: some View {
        Rectangle()
            .fill((colorScheme == .dark ? darkTheme.accent : Color.varqSaffron).opacity(colorScheme == .dark ? VarqOpacity.settingsDividerDark : VarqOpacity.settingsDividerLight))
            .frame(height: VarqLayout.settingsDividerHeight)
    }
}
