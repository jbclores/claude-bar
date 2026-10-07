import ClaudeBarCore
import Foundation
import UserNotifications

/// "🐈 <name> finished" notifications. Falls back to AppleScript when the notification center refuses
/// (e.g. an unsigned build or running outside an app bundle); a user who said no gets nothing.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// `sound` rides on the notification, so macOS Focus / Do Not Disturb mutes it with the banner. Where the
    /// notification center can't be used (the AppleScript fallback), `play` plays it instead.
    func post(_ event: FinishedEvent, sound: CatSound? = nil, play: @escaping @Sendable (CatSound) -> Void = { _ in }) {
        let title = "🐈 \(event.name) finished"
        let body = event.task ?? ""
        let fallback = { @Sendable in
            Self.osascript(title, body)
            if let sound { play(sound) }
        }
        guard Bundle.main.bundleIdentifier != nil else { return fallback() }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if error != nil { return fallback() }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let sound { content.sound = UNNotificationSound(named: UNNotificationSoundName("\(sound.rawValue).wav")) }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                if error != nil { fallback() }
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
