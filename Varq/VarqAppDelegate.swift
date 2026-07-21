import AppKit
import SwiftUI

final class VarqAppDelegate: NSObject, NSApplicationDelegate {
    private let sessionService = PrivateBookSessionService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appearance = UserDefaults.standard.string(forKey: "appAppearanceOverride") ?? "system"
        switch appearance {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionService.endApplicationSession()
    }
}
