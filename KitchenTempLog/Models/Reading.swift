import Foundation
import SwiftData

/// One recorded check. A reading outside the point's limits cannot be saved without a corrective
/// action, because that is the half of the record a health inspector actually asks about.
@Model
final class Reading {
    var id: UUID = UUID()
    var pointID: UUID = UUID()
    var locationID: UUID = UUID()
    /// The point's name at the time, so renaming a walk-in never rewrites last month's log.
    var pointName: String = ""
    var kindRaw: String = PointKind.cold.rawValue
    var date: Date = Date()
    var slotRaw: String = Slot.opening.rawValue
    var value: Double = 0
    var unitRaw: String = TempUnit.fahrenheit.rawValue
    /// The limits that applied when the reading was taken, kept so the log can be re-checked later.
    var minLimit: Double?
    var maxLimit: Double?
    var correctiveAction: String = ""
    var initials: String = ""
    var notes: String = ""

    init(point: LogPoint, slot: Slot, value: Double, unit: TempUnit, date: Date = .now) {
        self.id = UUID()
        self.pointID = point.id
        self.locationID = point.locationID
        self.pointName = point.displayName
        self.kindRaw = point.kindRaw
        self.date = date
        self.slotRaw = slot.rawValue
        self.value = value
        self.unitRaw = unit.rawValue
        self.minLimit = point.minLimit
        self.maxLimit = point.maxLimit
    }
}

extension Reading {
    var kind: PointKind { PointKind(rawValue: kindRaw) ?? .cold }
    var unit: TempUnit { TempUnit(rawValue: unitRaw) ?? .fahrenheit }
    var slot: Slot { Slot(rawValue: slotRaw) ?? .opening }
    var day: Date { Calendar.current.startOfDay(for: date) }

    var isInRange: Bool {
        if let minLimit, value < minLimit { return false }
        if let maxLimit, value > maxLimit { return false }
        return true
    }

    /// "38 °F" / "250 ppm"
    var valueText: String {
        kind.isChemical ? "\(Formatters.amount(value)) ppm" : "\(Formatters.amount(value)) \(unit.rawValue)"
    }
}

/// A kitchen, a truck, a cart. Points and readings belong to one.
@Model
final class Location {
    var id: UUID = UUID()
    var name: String = ""
    var licenseNumber: String = ""
    var manager: String = ""
    var unitRaw: String = TempUnit.fahrenheit.rawValue
    /// The hour the kitchen opens, which is what the slot reminders are hung off.
    var openingHour: Int = 7
    var remindersOn: Bool = false
    var createdAt: Date = Date()

    init(name: String = "", unit: TempUnit = .fahrenheit) {
        self.id = UUID()
        self.name = name
        self.unitRaw = unit.rawValue
        self.createdAt = .now
    }
}

extension Location {
    var unit: TempUnit {
        get { TempUnit(rawValue: unitRaw) ?? .fahrenheit }
        set { unitRaw = newValue.rawValue }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Kitchen" : trimmed
    }
}
