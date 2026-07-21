import AppKit
import SwiftUI

final class VarqAppDelegate: NSObject, NSApplicationDelegate {
    private let sessionService = PrivateBookSessionService()

    func applicationWillTerminate(_ notification: Notification) {
        sessionService.endApplicationSession()
    }
}
