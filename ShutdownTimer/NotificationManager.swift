import UserNotifications

final class NotificationManager: NSObject, TimerNotifying, UNUserNotificationCenterDelegate {
    static let categoryIdentifier = "com.zeeshan.ShutdownTimer.warning"
    static let cancelActionIdentifier = "com.zeeshan.ShutdownTimer.cancel"
    static let snoozeActionIdentifier = "com.zeeshan.ShutdownTimer.snooze"

    var onCancel: (() -> Void)?
    var onSnooze: (() -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        registerCategory()
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postWarning(for action: PowerAction) {
        let content = UNMutableNotificationContent()
        content.title = "Shutdown Timer"
        content.body = "Mac will \(action.displayName.lowercased()) in 1 minute."
        content.categoryIdentifier = Self.categoryIdentifier

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    func postPermissionError(for action: PowerAction) {
        let content = UNMutableNotificationContent()
        content.title = "Shutdown Timer"
        content.body = "Couldn't \(action.displayName.lowercased()) your Mac. Check System Settings > Privacy & Security > Automation."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    private func registerCategory() {
        let cancelAction = UNNotificationAction(identifier: Self.cancelActionIdentifier, title: "Cancel", options: [])
        let snoozeAction = UNNotificationAction(identifier: Self.snoozeActionIdentifier, title: "Snooze 10 min", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [cancelAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case Self.cancelActionIdentifier:
            onCancel?()
        case Self.snoozeActionIdentifier:
            onSnooze?()
        default:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
