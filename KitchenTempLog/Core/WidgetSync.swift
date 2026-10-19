import Foundation
import WidgetKit

enum WidgetSync {
    /// Recomputes the widget summary from today's shift list and reloads timelines.
    static func update(location: Location?, points: [LogPoint], readings: [Reading], cooling: [CoolingRecord]) {
        let today = SafetyMath.readings(readings, on: .now)
        let outstanding = SafetyMath.outstanding(points, readings: readings, on: .now)
        let active = SafetyMath.active(cooling)
        var snapshot = WidgetSnapshot()
        snapshot.locationName = location?.displayName ?? ""
        snapshot.expectedToday = SafetyMath.expected(points).count
        snapshot.doneToday = today.count
        snapshot.outOfRangeToday = today.filter { !$0.isInRange }.count
        snapshot.nextDue = outstanding.first.flatMap { due in points.first { $0.id == due.pointID }?.displayName }
        snapshot.coolingActive = active.count
        snapshot.coolingDeadline = active.compactMap(\.nextDeadline).min()
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
