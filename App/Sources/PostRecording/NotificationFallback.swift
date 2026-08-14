import Foundation
import UserNotifications

enum NotificationFallback {
    static func postRecordingSaved(url: URL) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Recording saved")
            content.body = url.lastPathComponent
            center.add(
                UNNotificationRequest(
                    identifier: url.absoluteString,
                    content: content,
                    trigger: nil
                )
            )
        }
    }
}
