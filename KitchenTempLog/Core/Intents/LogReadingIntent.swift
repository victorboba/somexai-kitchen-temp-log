import AppIntents
import Foundation

/// "Log a temperature in Temp Log" from Siri, Spotlight or Shortcuts. Opens the shift list.
struct LogReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Temperature"
    static var description = IntentDescription("Opens Temp Log on today's shift list.")
    static var openAppWhenRun = true

    static let pendingKey = "intent.openShiftList"

    func perform() async throws -> some IntentResult {
        WidgetSnapshot.defaults.set(true, forKey: Self.pendingKey)
        return .result()
    }
}

struct KitchenTempLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogReadingIntent(),
            phrases: ["Log a temperature in \(.applicationName)", "Open the shift list in \(.applicationName)"],
            shortTitle: "Log a Temperature",
            systemImageName: "thermometer.medium"
        )
    }
}
