import Foundation

/// A tiny summary the app writes to the shared App Group so the widget can render
/// without touching SwiftData.
struct WidgetSnapshot: Codable {
    var locationName: String = ""
    var doneToday: Int = 0
    var expectedToday: Int = 0
    var outOfRangeToday: Int = 0
    var nextDue: String?
    var coolingActive: Int = 0
    var coolingDeadline: Date?
    var updatedAt: Date = .now

    static let storageKey = "widget.snapshot"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    static func load() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults.set(data, forKey: Self.storageKey)
    }

    static let placeholder = WidgetSnapshot(locationName: "Front Kitchen", doneToday: 7, expectedToday: 12,
                                            outOfRangeToday: 1, nextDue: "Walk-in cooler",
                                            coolingActive: 1, coolingDeadline: Date().addingTimeInterval(3600))
}
