import AppKit
import UserNotifications

@MainActor
final class ReadingAssistantCompletionService {
    func announceCompletion(title: String) {
        if NSApp.isActive {
            NSSound(named: "Glass")?.play()
            return
        }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            let updatedSettings = await center.notificationSettings()
            guard updatedSettings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Reading aid ready"
            content.body = title
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
