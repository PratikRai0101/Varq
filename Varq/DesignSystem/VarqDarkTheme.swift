import SwiftUI

enum VarqDarkTheme: Sendable {
    case indigo
    case black
    case monochrome

    var background: Color {
        switch self {
        case .indigo: .varqIndigo
        case .black, .monochrome: .varqBlack
        }
    }

    var surface: Color {
        switch self {
        case .indigo: .varqIndigoLight
        case .black: .varqBlackSurface
        case .monochrome: .varqMonochromeSurface
        }
    }

    var primaryText: Color {
        switch self {
        case .indigo, .black: .varqInkDark
        case .monochrome: .varqMonochromeInk
        }
    }

    var accent: Color {
        switch self {
        case .indigo, .black: .varqSaffron
        case .monochrome: .varqMonochromeInk
        }
    }

    var destructiveAccent: Color {
        switch self {
        case .indigo, .black: .varqMaroon
        case .monochrome: .varqMonochromeInk
        }
    }
}

private struct VarqDarkThemeKey: EnvironmentKey {
    static let defaultValue: VarqDarkTheme = .indigo
}

extension EnvironmentValues {
    var varqDarkTheme: VarqDarkTheme {
        get { self[VarqDarkThemeKey.self] }
        set { self[VarqDarkThemeKey.self] = newValue }
    }
}
