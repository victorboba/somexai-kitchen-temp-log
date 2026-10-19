import Foundation
import SwiftData

#if DEBUG
/// Four weeks of a small restaurant's logs, used for screenshots and manual testing.
enum SampleData {
    private struct PointSeed {
        let name: String
        let kind: PointKind
        let min: Double?
        let max: Double?
        let slots: [Slot]
        /// Roughly how often this unit drifts out of range, so the report has something to show.
        let failureRate: Double
        /// The middle of the normal band, used to make readings look like a real thermometer.
        let centre: Double
    }

    static func insert(into context: ModelContext) {
        let location = Location(name: "Front Kitchen", unit: .fahrenheit)
        location.licenseNumber = "FS-2026-4471"
        location.manager = "R. Alvarez"
        location.openingHour = 7
        context.insert(location)

        let seeds = [
            PointSeed(name: "Walk-in cooler", kind: .cold, min: nil, max: 41, slots: [.opening, .midday, .closing], failureRate: 0.04, centre: 37),
            PointSeed(name: "Reach-in cooler", kind: .cold, min: nil, max: 41, slots: [.opening, .closing], failureRate: 0.14, centre: 39),
            PointSeed(name: "Walk-in freezer", kind: .frozen, min: nil, max: 0, slots: [.opening, .closing], failureRate: 0.03, centre: -6),
            PointSeed(name: "Hot well, soup", kind: .hot, min: 135, max: nil, slots: [.midday, .closing], failureRate: 0.08, centre: 152),
            PointSeed(name: "Prep line rail", kind: .cold, min: nil, max: 41, slots: [.midday], failureRate: 0.10, centre: 38),
            PointSeed(name: "Sanitiser bucket", kind: .sanitizer, min: 200, max: 400, slots: [.opening, .midday, .closing], failureRate: 0.07, centre: 290),
        ]

        var points: [LogPoint] = []
        for (index, seed) in seeds.enumerated() {
            let point = LogPoint(locationID: location.id, name: seed.name, kind: seed.kind,
                                 minLimit: seed.min, maxLimit: seed.max, slots: seed.slots)
            point.sortIndex = index
            context.insert(point)
            points.append(point)
        }

        let calendar = Calendar.current
        var generator = SystemRandomNumberGenerator()
        let fixes = ["Moved product to the walk-in", "Adjusted thermostat, rechecking", "Called for service", "Discarded product", "Remade the solution"]

        for offset in stride(from: 27, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            if calendar.component(.weekday, from: day) == 2 { continue }   // closed Mondays
            for (seed, point) in zip(seeds, points) {
                for slot in seed.slots {
                    // Today's later slots have not happened yet, which is what makes the shift list look real.
                    if offset == 0 && slot != .opening { continue }
                    guard Double.random(in: 0...1, using: &generator) > 0.04 else { continue }  // the odd missed check
                    let hour = location.openingHour + slot.hourOffset
                    guard let at = calendar.date(bySettingHour: min(hour, 23),
                                                 minute: Int.random(in: 0...45, using: &generator),
                                                 second: 0, of: day) else { continue }
                    let failed = Double.random(in: 0...1, using: &generator) < seed.failureRate
                    let value = reading(for: seed, failed: failed, using: &generator)
                    let record = Reading(point: point, slot: slot, value: value, unit: location.unit, date: at)
                    record.initials = ["RA", "JM", "TP"].randomElement(using: &generator) ?? "RA"
                    if !record.isInRange {
                        record.correctiveAction = fixes.randomElement(using: &generator) ?? fixes[0]
                    }
                    context.insert(record)
                }
            }
        }

        insertCooling(into: context, location: location, calendar: calendar, generator: &generator)
        try? context.save()
    }

    private static func reading(for seed: PointSeed, failed: Bool, using generator: inout SystemRandomNumberGenerator) -> Double {
        guard failed else {
            return (seed.centre + Double.random(in: -2.5...2.5, using: &generator)).rounded()
        }
        if let max = seed.max, seed.kind != .sanitizer { return (max + Double.random(in: 1...7, using: &generator)).rounded() }
        if let min = seed.min, seed.kind == .sanitizer { return (min - Double.random(in: 20...90, using: &generator)).rounded() }
        if let min = seed.min { return (min - Double.random(in: 2...12, using: &generator)).rounded() }
        return seed.centre
    }

    private static func insertCooling(into context: ModelContext, location: Location,
                                      calendar: Calendar, generator: inout SystemRandomNumberGenerator) {
        let items = ["Chili", "Chicken stock", "Rice", "Pulled pork", "Marinara"]
        for offset in [0, 1, 2, 4, 6, 9, 13] {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now),
                  let started = calendar.date(bySettingHour: 14, minute: Int.random(in: 0...50, using: &generator), second: 0, of: day)
            else { continue }
            let record = CoolingRecord(locationID: location.id,
                                       item: items[offset % items.count],
                                       startTemp: Double(Int.random(in: 160...190, using: &generator)),
                                       unit: location.unit,
                                       stageOneTarget: 70, stageOneMinutes: 120,
                                       stageTwoTarget: 41, stageTwoMinutes: 360,
                                       startedAt: started)
            record.batchSize = ["4 qt", "6 qt", "2 hotel pans", "8 qt"].randomElement(using: &generator) ?? "4 qt"
            record.initials = "RA"

            if offset == 0 {
                // One batch still on the clock, so the Cooling tab has a live countdown in the screenshot.
                record.startedAt = Date().addingTimeInterval(-45 * 60)
                context.insert(record)
                continue
            }
            let late = offset == 4
            record.stageOneAt = record.startedAt.addingTimeInterval(TimeInterval(late ? 8100 : Int.random(in: 4200...6600, using: &generator)))
            record.stageOneTemp = late ? 78 : Double(Int.random(in: 58...68, using: &generator))
            record.stageTwoAt = record.startedAt.addingTimeInterval(TimeInterval(Int.random(in: 15000...20400, using: &generator)))
            record.stageTwoTemp = Double(Int.random(in: 34...40, using: &generator))
            record.stage = SafetyMath.evaluate(record)
            if record.stage == .failed { record.correctiveAction = "Discarded, cooled in smaller pans next time" }
            context.insert(record)
        }
    }
}
#endif
