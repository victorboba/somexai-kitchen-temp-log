import Foundation

/// Every number the app reports, with no SwiftData dependency so it can be tested directly.
/// Nothing here sets a limit: it compares readings against the limits the operator entered.
enum SafetyMath {

    // MARK: Filtering

    static func readings(_ readings: [Reading], at locationID: UUID) -> [Reading] {
        readings.filter { $0.locationID == locationID }
    }

    static func readings(_ readings: [Reading], on day: Date) -> [Reading] {
        let start = Calendar.current.startOfDay(for: day)
        return readings.filter { $0.day == start }
    }

    static func readings(_ readings: [Reading], from start: Date, to end: Date) -> [Reading] {
        let calendar = Calendar.current
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        return readings.filter { $0.date >= lower && $0.date < upper }
    }

    // MARK: The shift list

    struct Due: Identifiable, Equatable {
        let pointID: UUID
        let slot: Slot
        var id: String { "\(pointID)-\(slot.rawValue)" }
    }

    /// Every point-and-slot combination expected on one day, in setup order then slot order.
    static func expected(_ points: [LogPoint]) -> [Due] {
        points.filter { !$0.archived }
              .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
              .flatMap { point in point.slots.map { Due(pointID: point.id, slot: $0) } }
    }

    /// The reading that satisfies a slot, if one has been taken.
    static func reading(for due: Due, in readings: [Reading], on day: Date) -> Reading? {
        let onDay = self.readings(readings, on: day)
        return onDay.first { $0.pointID == due.pointID && $0.slot == due.slot }
    }

    /// Expected checks with nothing recorded for the day.
    static func outstanding(_ points: [LogPoint], readings: [Reading], on day: Date) -> [Due] {
        expected(points).filter { reading(for: $0, in: readings, on: day) == nil }
    }

    // MARK: Compliance

    struct Summary: Equatable {
        var expected: Int = 0
        var recorded: Int = 0
        var inRange: Int = 0
        var outOfRange: Int = 0
        var missingCorrectiveAction: Int = 0

        var completionRate: Double { expected > 0 ? Double(recorded) / Double(expected) : 0 }
        var inRangeRate: Double { recorded > 0 ? Double(inRange) / Double(recorded) : 0 }
    }

    /// Counts over a date range. `expected` multiplies the current schedule by the days in the range,
    /// which is the only honest estimate when the schedule can be edited.
    static func summary(_ points: [LogPoint], readings: [Reading], from start: Date, to end: Date) -> Summary {
        let scoped = self.readings(readings, from: start, to: end)
        let days = dayCount(from: start, to: end)
        var summary = Summary()
        summary.expected = expected(points).count * days
        summary.recorded = scoped.count
        summary.inRange = scoped.filter(\.isInRange).count
        summary.outOfRange = scoped.count - summary.inRange
        summary.missingCorrectiveAction = scoped.filter {
            !$0.isInRange && $0.correctiveAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return summary
    }

    static func dayCount(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.startOfDay(for: end)
        return max(1, (calendar.dateComponents([.day], from: lower, to: upper).day ?? 0) + 1)
    }

    // MARK: Series and breakdowns

    struct DayStat: Identifiable, Equatable {
        let day: Date
        let recorded: Int
        let outOfRange: Int
        var id: Date { day }
    }

    static func dailySeries(_ readings: [Reading], from start: Date, to end: Date) -> [DayStat] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        var result: [DayStat] = []
        while day <= last {
            let onDay = self.readings(readings, on: day)
            result.append(DayStat(day: day, recorded: onDay.count, outOfRange: onDay.filter { !$0.isInRange }.count))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    struct PointStat: Identifiable, Equatable {
        let pointName: String
        let recorded: Int
        let outOfRange: Int
        var id: String { pointName }
        var outOfRangeRate: Double { recorded > 0 ? Double(outOfRange) / Double(recorded) : 0 }
    }

    /// Which equipment fails most, worst first. It is the line a manager acts on.
    static func byPoint(_ readings: [Reading]) -> [PointStat] {
        var totals: [String: (recorded: Int, out: Int)] = [:]
        for reading in readings {
            var entry = totals[reading.pointName] ?? (0, 0)
            entry.recorded += 1
            if !reading.isInRange { entry.out += 1 }
            totals[reading.pointName] = entry
        }
        return totals
            .map { PointStat(pointName: $0.key, recorded: $0.value.recorded, outOfRange: $0.value.out) }
            .sorted { ($0.outOfRange, $0.outOfRangeRate) > ($1.outOfRange, $1.outOfRangeRate) }
    }

    // MARK: Cooling

    /// Evaluates a batch against the two checkpoints the operator entered. A stage that was recorded
    /// late counts as out of limit even if the temperature was right, which is how the rule works.
    static func evaluate(_ record: CoolingRecord) -> CoolingStage {
        if record.stage == .discarded { return .discarded }
        guard let oneAt = record.stageOneAt, let oneTemp = record.stageOneTemp else { return .running }
        if oneAt > record.stageOneDeadline || oneTemp > record.stageOneTarget { return .failed }
        guard let twoAt = record.stageTwoAt, let twoTemp = record.stageTwoTemp else { return .running }
        if twoAt > record.stageTwoDeadline || twoTemp > record.stageTwoTarget { return .failed }
        return .passed
    }

    static func active(_ records: [CoolingRecord]) -> [CoolingRecord] {
        records.filter { evaluate($0) == .running }.sorted { $0.startedAt < $1.startedAt }
    }

    /// Seconds until the next checkpoint; negative once it has passed.
    static func secondsToDeadline(_ record: CoolingRecord, now: Date = .now) -> Int? {
        guard let deadline = record.nextDeadline else { return nil }
        return Int(deadline.timeIntervalSince(now))
    }
}
