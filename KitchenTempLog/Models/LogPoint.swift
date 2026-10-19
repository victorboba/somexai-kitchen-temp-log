import Foundation
import SwiftData

/// What kind of check this is. The kind decides the unit, the shape of the limits and the wording,
/// so one model covers a walk-in, a hot well, a delivery and a sanitiser bucket.
enum PointKind: String, Codable, CaseIterable, Identifiable {
    case cold, frozen, hot, cooking, receiving, sanitizer, ambient
    var id: String { rawValue }

    var name: String {
        switch self {
        case .cold: return "Cold holding"
        case .frozen: return "Frozen storage"
        case .hot: return "Hot holding"
        case .cooking: return "Cooking"
        case .receiving: return "Receiving"
        case .sanitizer: return "Sanitiser"
        case .ambient: return "Room"
        }
    }

    var symbol: String {
        switch self {
        case .cold: return "refrigerator.fill"
        case .frozen: return "snowflake"
        case .hot: return "flame.fill"
        case .cooking: return "thermometer.high"
        case .receiving: return "shippingbox.fill"
        case .sanitizer: return "drop.triangle.fill"
        case .ambient: return "thermometer.medium"
        }
    }

    /// Sanitiser is measured in parts per million; everything else is a temperature.
    var isChemical: Bool { self == .sanitizer }

    /// Hot holding and cooking have a floor and no ceiling; the cold kinds have a ceiling.
    var hasUpperLimit: Bool {
        switch self {
        case .cold, .frozen, .receiving, .ambient, .sanitizer: return true
        case .hot, .cooking: return false
        }
    }

    var hasLowerLimit: Bool {
        switch self {
        case .hot, .cooking, .sanitizer, .ambient: return true
        case .cold, .frozen, .receiving: return false
        }
    }

    /// Offered when a point is created. The user confirms or changes them, because the numbers
    /// that matter are the ones their own health department enforces.
    func suggestedLimits(_ unit: TempUnit) -> (min: Double?, max: Double?) {
        switch self {
        case .cold:      return (nil, unit == .fahrenheit ? 41 : 5)
        case .frozen:    return (nil, unit == .fahrenheit ? 0 : -18)
        case .hot:       return (unit == .fahrenheit ? 135 : 57, nil)
        case .cooking:   return (unit == .fahrenheit ? 165 : 74, nil)
        case .receiving: return (nil, unit == .fahrenheit ? 41 : 5)
        case .ambient:   return (unit == .fahrenheit ? 60 : 16, unit == .fahrenheit ? 75 : 24)
        case .sanitizer: return (200, 400)
        }
    }
}

enum TempUnit: String, Codable, CaseIterable, Identifiable {
    case fahrenheit = "°F", celsius = "°C"
    var id: String { rawValue }
    var name: String { self == .fahrenheit ? "Fahrenheit" : "Celsius" }
}

/// When in the day a check is due. A point can be due in more than one slot.
enum Slot: String, Codable, CaseIterable, Identifiable {
    case opening, midday, closing
    var id: String { rawValue }
    var name: String {
        switch self {
        case .opening: return "Opening"
        case .midday: return "Midday"
        case .closing: return "Closing"
        }
    }
    var symbol: String {
        switch self {
        case .opening: return "sunrise.fill"
        case .midday: return "sun.max.fill"
        case .closing: return "moon.fill"
        }
    }
    /// The hour the reminder fires, offset from the location's opening hour.
    var hourOffset: Int {
        switch self {
        case .opening: return 0
        case .midday: return 5
        case .closing: return 10
        }
    }
}

/// One place a reading is taken: a walk-in, a hot well, a prep line, a sanitiser bucket.
@Model
final class LogPoint {
    var id: UUID = UUID()
    var locationID: UUID = UUID()
    var name: String = ""
    var kindRaw: String = PointKind.cold.rawValue
    /// Nil means the limit does not apply to this kind.
    var minLimit: Double?
    var maxLimit: Double?
    /// "opening|closing" — which slots this point is due in.
    var slotsEncoded: String = Slot.opening.rawValue
    var sortIndex: Int = 0
    var archived: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()

    init(locationID: UUID, name: String = "", kind: PointKind = .cold,
         minLimit: Double? = nil, maxLimit: Double? = nil, slots: [Slot] = [.opening, .closing]) {
        self.id = UUID()
        self.locationID = locationID
        self.name = name
        self.kindRaw = kind.rawValue
        self.minLimit = minLimit
        self.maxLimit = maxLimit
        self.slotsEncoded = LogPoint.encode(slots)
        self.createdAt = .now
    }
}

extension LogPoint {
    static func encode(_ slots: [Slot]) -> String {
        Slot.allCases.filter { slots.contains($0) }.map(\.rawValue).joined(separator: "|")
    }

    var kind: PointKind {
        get { PointKind(rawValue: kindRaw) ?? .cold }
        set { kindRaw = newValue.rawValue }
    }

    var slots: [Slot] {
        get { slotsEncoded.split(separator: "|").compactMap { Slot(rawValue: String($0)) } }
        set { slotsEncoded = LogPoint.encode(newValue) }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.name : trimmed
    }

    /// "41 °F or below" / "135 °F or above" / "200 to 400 ppm"
    func limitText(_ unit: TempUnit) -> String {
        let suffix = kind.isChemical ? " ppm" : " \(unit.rawValue)"
        switch (minLimit, maxLimit) {
        case let (min?, max?): return "\(Formatters.amount(min)) to \(Formatters.amount(max))\(suffix)"
        case let (nil, max?):  return "\(Formatters.amount(max))\(suffix) or below"
        case let (min?, nil):  return "\(Formatters.amount(min))\(suffix) or above"
        default:               return "No limit set"
        }
    }
}
