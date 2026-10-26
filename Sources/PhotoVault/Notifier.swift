import Foundation
import UserNotifications

/// Posts a macOS notification. `UNUserNotificationCenter` only works for a real .app
/// bundle, so under `swift run` this falls back to AppleScript's `display notification`.
enum Notifier {
    private static var hasBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func post(title: String, body: String) {
        if hasBundle {
            postWithCenter(title: title, body: body)
        } else {
            postWithAppleScript(title: title, body: body)
        }
    }

    private static func postWithCenter(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return NSLog("PhotoVault: notifications not allowed") }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                if let error { NSLog("PhotoVault: notification failed: \(error)") }
            }
        }
    }

    private static func postWithAppleScript(title: String, body: String) {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \(quoted(body)) with title \(quoted(title))"]
        do { try process.run() } catch { NSLog("PhotoVault: notification failed: \(error)") }
    }
}
