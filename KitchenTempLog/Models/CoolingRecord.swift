import Foundation
import SwiftData

/// Where a cooling batch has got to.
enum CoolingStage: String, Codable, CaseIterable, Identifiable {
    case running, passed, failed, discarded
    var id: String { rawValue }

    var name: String {
        switch self {
        case .running: return "Cooling"
        case .passed: return "Passed"
        case .failed: return "Out of limit"
        case .discarded: return "Discarded"
        }
    }

    var symbol: String {
        switch self {
        case .running: return "timer"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .discarded: return "trash.circle.fill"
        }
    }
}

/// A two-stage cooling record. The user sets the two checkpoints themselves in Setup;
/// the app only runs the clock they entered and records what the thermometer said.
@Model
final class CoolingRecord {
    var id: UUID = UUID()
    var locationID: UUID = UUID()
    var item: String = ""
    var batchSize: String = ""
    var startedAt: Date = Date()
    var startTemp: Double = 0
    var unitRaw: String = TempUnit.fahrenheit.rawValue

    /// Stage one: down to `stageOneTarget` within `stageOneMinutes`.
    var stageOneTarget: Double = 70
    var stageOneMinutes: Int = 120
    var stageOneAt: Date?
    var stageOneTemp: Double?

    /// Stage two: down to `stageTwoTarget` within `stageTwoMinutes` of the start.
    var stageTwoTarget: Double = 41
    var stageTwoMinutes: Int = 360
    var stageTwoAt: Date?
    var stageTwoTemp: Double?

    var stageRaw: String = CoolingStage.running.rawValue
    var correctiveAction: String = ""
    var initials: String = ""
    var notes: String = ""

    init(locationID: UUID, item: String, startTemp: Double, unit: TempUnit,
         stageOneTarget: Double, stageOneMinutes: Int, stageTwoTarget: Double, stageTwoMinutes: Int,
         startedAt: Date = .now) {
        self.id = UUID()
        self.locationID = locationID
        self.item = item
        self.startTemp = startTemp
        self.unitRaw = unit.rawValue
        self.stageOneTarget = stageOneTarget
        self.stageOneMinutes = stageOneMinutes
        self.stageTwoTarget = stageTwoTarget
        self.stageTwoMinutes = stageTwoMinutes
        self.startedAt = startedAt
    }
}

extension CoolingRecord {
    var unit: TempUnit { TempUnit(rawValue: unitRaw) ?? .fahrenheit }
    var day: Date { Calendar.current.startOfDay(for: startedAt) }

    var stage: CoolingStage {
        get { CoolingStage(rawValue: stageRaw) ?? .running }
        set { stageRaw = newValue.rawValue }
    }

    var displayItem: String {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Batch" : trimmed
    }

    var stageOneDeadline: Date { startedAt.addingTimeInterval(TimeInterval(stageOneMinutes * 60)) }
    var stageTwoDeadline: Date { startedAt.addingTimeInterval(TimeInterval(stageTwoMinutes * 60)) }

    /// The checkpoint the batch is working towards, or nil once both are recorded.
    var nextDeadline: Date? {
        if stageOneAt == nil { return stageOneDeadline }
        if stageTwoAt == nil { return stageTwoDeadline }
        return nil
    }

    func temperature(_ value: Double) -> String { "\(Formatters.amount(value)) \(unit.rawValue)" }
}
