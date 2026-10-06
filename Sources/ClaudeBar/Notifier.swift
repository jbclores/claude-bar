import ClaudeBarCore
import Foundation
import UserNotifications

/// "🐈 <name> finished" notifications. Falls back to AppleScript when the notification center refuses
/// (e.g. an unsigned build or running outside an app bundle); a user who said no gets nothing.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    func post(_ event: FinishedEvent) {
        let title = "🐈 \(event.name) finished"
        let body = event.task ?? ""
        guard Bundle.main.bundleIdentifier != nil else { return Self.osascript(title, body) }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if error != nil { return Self.osascript(title, body) }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                if error != nil { Self.osascript(title, body) }
            }
        }
    }

    // Show banners even while the dropdown makes ClaudeBar the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private static func osascript(_ title: String, _ body: String) {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \(quoted(body)) with title \(quoted(title))"]
        try? p.run()
    }
}
