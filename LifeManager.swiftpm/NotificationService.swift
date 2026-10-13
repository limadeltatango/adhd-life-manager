import Foundation
import UserNotifications

// Local notifications only. No APNs, background polling, server, or paid services.
enum NotificationActionID {
    static let category = "LIFEMANAGER_OPEN_LOOP"
    static let reportedDone = "LIFEMANAGER_REPORTED_DONE"
    static let snooze = "LIFEMANAGER_SNOOZE"
    static let skip = "LIFEMANAGER_SKIP"
    static let loopKey = "lifeManagerLoopID"
}

enum NotificationProblem: LocalizedError {
    case permissionDenied
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notifications are turned off. Enable them in iPad or iPhone Settings to receive prompts. Your task is still saved."
        case .invalidDate:
            return "The reminder time must be in the future. Your task is still saved."
        }
    }
}

@MainActor
final class LocalNotificationService {
    static let shared = LocalNotificationService()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func registerActions() {
        let done = UNNotificationAction(
            identifier: NotificationActionID.reportedDone,
            title: "I did it",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: NotificationActionID.snooze,
            title: "Snooze",
            options: []
        )
        let skip = UNNotificationAction(
            identifier: NotificationActionID.skip,
            title: "Skip for now",
            options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: NotificationActionID.category,
                actions: [done, snooze, skip],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    func permissionDescription() async -> String {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return "Not requested"
        case .denied: return "Off — enable in device Settings"
        case .authorized: return "Allowed"
        case .provisional: return "Quiet notifications allowed"
        case .ephemeral: return "Temporarily allowed"
        @unknown default: return "Unknown"
        }
    }

    @discardableResult
    func requestPermission() async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            throw NotificationProblem.permissionDenied
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if !granted { throw NotificationProblem.permissionDenied }
            return granted
        @unknown default:
            throw NotificationProblem.permissionDenied
        }
    }

    func cancel(_ id: UUID) {
        let requestID = Self.identifier(for: id)
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
    }

    func schedule(_ loop: LifeLoop, playSound: Bool) async throws {
        cancel(loop.id)
        guard loop.kind == .task,
              loop.state == .open,
              let date = loop.remindAt else { return }
        guard date.timeIntervalSinceNow > 0 else { return }
        try await requestPermission()

        let content = UNMutableNotificationContent()
        content.title = "Life Manager"
        content.body = loop.title
        content.subtitle = "Still open — choose an action"
        content.categoryIdentifier = NotificationActionID.category
        content.userInfo = [NotificationActionID.loopKey: loop.id.uuidString]
        content.sound = playSound ? .default : nil

        // A time-interval trigger is independent of timezone and works when the app closes.
        let delay = max(1.0, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: loop.id),
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    private static func identifier(for id: UUID) -> String {
        "life-manager.loop.\(id.uuidString)"
    }
}

// The delegate is registered on launch. Action handling uses the same disk-backed
// store as the UI, so an action isn't lost just because the view isn't visible.
final class LifeNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LifeNotificationRouter()

    private override init() { super.init() }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let idString = response.notification.request.content.userInfo[NotificationActionID.loopKey] as? String
        let identifier = response.actionIdentifier

        Task { @MainActor in
            defer { completionHandler() }
            guard let idString, let loopID = UUID(uuidString: idString) else { return }
            switch identifier {
            case NotificationActionID.reportedDone:
                await TaskStore.shared.applyNotificationAction(.reportedDone, to: loopID)
            case NotificationActionID.snooze:
                await TaskStore.shared.applyNotificationAction(.snoozed, to: loopID)
            case NotificationActionID.skip:
                await TaskStore.shared.applyNotificationAction(.skipped, to: loopID)
            default:
                // Opening/dismissing a notification isn't treated as doing the task.
                break
            }
        }
    }
}
