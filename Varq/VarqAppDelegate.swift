import AppKit
import SwiftUI

final class VarqAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = UserDefaultsAppSettingsStore().load()
        AppAppearance.apply(settings.appearance)
    }

}

@MainActor
extension AppAppearance {
    static func apply(_ appearance: AppAppearance) {
        switch appearance {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .indigo, .black, .monochrome:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil
        }
    }
}
