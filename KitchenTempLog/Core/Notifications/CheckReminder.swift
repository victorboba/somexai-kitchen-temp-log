import Foundation
import UserNotifications

/// Two kinds of nudge: the shift slots, hung off the hour the kitchen opens, and the cooling
/// checkpoints, which are one-off and exact. Both times come from what the operator entered.
enum CheckReminder {
    static let enabledKey = "reminder.shift.enabled"
    static let slotPrefix = "shift.slot."
    static let coolingPrefix = "cooling."

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func ensurePermission() async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") { return false }
        #endif
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied: return false
        default: return true
        }
    }

    /// One repeating reminder per slot that has at least one check point on it.
    static func reschedule(location: Location?, points: [LogPoint]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(slotPrefix) })
        guard isEnabled, let location, await ensurePermission() else { return }

        for slot in Slot.allCases {
            let count = points.filter { !$0.archived && $0.slots.contains(slot) }.count
            guard count > 0 else { continue }
            var components = DateComponents()
            components.hour = (location.openingHour + slot.hourOffset) % 24
            components.minute = 0
            let content = UNMutableNotificationContent()
            content.title = "\(slot.name) checks"
            content.body = count == 1 ? "One check due at \(location.displayName)." : "\(count) checks due at \(location.displayName)."
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: "\(slotPrefix)\(slot.rawValue)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        }
    }

    /// A one-off alert ten minutes before a cooling checkpoint, so the batch is not missed.
    static func scheduleCooling(_ record: CoolingRecord) async {
        guard let deadline = record.nextDeadline, await ensurePermission() else { return }
        let fireAt = deadline.addingTimeInterval(-600)
        guard fireAt > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Cooling check due"
        content.body = "\(record.displayItem) needs a temperature by \(Formatters.time.string(from: deadline))."
        content.sound = .default
        let interval = fireAt.timeIntervalSinceNow
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "\(coolingPrefix)\(record.id.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
    }

    static func cancelCooling(_ record: CoolingRecord) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["\(coolingPrefix)\(record.id.uuidString)"])
    }
}
