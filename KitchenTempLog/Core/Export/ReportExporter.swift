import UIKit

/// The pack an inspector asks for: the limits in force, every reading, every failure with what was
/// done about it, and every cooling batch. It reports what was recorded and judges nothing else.
enum ReportExporter {
    static func export(location: Location, points: [LogPoint], readings: [Reading], cooling: [CoolingRecord],
                       from start: Date, to end: Date, periodLabel: String) throws -> URL {
        let scoped = readings.sorted { $0.date < $1.date }
        let batches = cooling.sorted { $0.startedAt < $1.startedAt }
        let footer = "\(AppConfig.storeName) · \(location.displayName)"

        return try PDFCanvas.render(footer: footer) { page in
            page.title("Food Safety Temperature Log")
            page.subtitle("\(location.displayName) · \(periodLabel) · \(Formatters.date.string(from: start)) to \(Formatters.date.string(from: end))")
            if !location.licenseNumber.isEmpty { page.subtitle("Permit \(location.licenseNumber)") }
            if !location.manager.isEmpty { page.subtitle("Person in charge: \(location.manager)") }
            page.subtitle("Prepared \(Formatters.dateTime.string(from: .now))")

            summary(page, points: points, readings: scoped, from: start, to: end)
            limits(page, points: points, unit: location.unit)
            failures(page, readings: scoped)
            equipment(page, readings: scoped)
            coolingSection(page, records: batches)
            log(page, readings: scoped)

            page.heading("About this log")
            page.paragraph(AppConfig.disclaimer, color: .darkGray)
        }
    }

    // MARK: Sections

    private static func summary(_ page: PDFCanvas, points: [LogPoint], readings: [Reading], from start: Date, to end: Date) {
        let s = SafetyMath.summary(points, readings: readings, from: start, to: end)
        page.heading("Summary")
        page.keyValues([
            ("Days covered", "\(SafetyMath.dayCount(from: start, to: end))"),
            ("Checks recorded", "\(s.recorded) of \(s.expected) scheduled · \(Formatters.percent(s.completionRate))"),
            ("Within limits", "\(s.inRange) of \(s.recorded) · \(Formatters.percent(s.inRangeRate))"),
            ("Outside limits", "\(s.outOfRange)"),
            ("Failures without a corrective action", "\(s.missingCorrectiveAction)"),
        ])
    }

    private static func limits(_ page: PDFCanvas, points: [LogPoint], unit: TempUnit) {
        let active = points.filter { !$0.archived }.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
        guard !active.isEmpty else { return }
        page.heading("Check points and the limits in force")
        page.table(headers: ["Check point", "Kind", "Limit", "Due"],
                   widths: [0.34, 0.2, 0.26, 0.2],
                   rows: active.map { point in
                       [point.displayName, point.kind.name, point.limitText(unit),
                        point.slots.map(\.name).joined(separator: ", ")]
                   })
    }

    private static func failures(_ page: PDFCanvas, readings: [Reading]) {
        let failed = readings.filter { !$0.isInRange }
        guard !failed.isEmpty else { return }
        page.heading("Outside limits, and what was done")
        page.table(headers: ["When", "Check point", "Reading", "Limit", "Corrective action", "By"],
                   widths: [0.17, 0.19, 0.11, 0.14, 0.31, 0.08],
                   rows: failed.map { reading in
                       [Formatters.dateTime.string(from: reading.date),
                        reading.pointName,
                        reading.valueText,
                        limitCell(reading),
                        reading.correctiveAction.isEmpty ? "NOT RECORDED" : reading.correctiveAction.replacingOccurrences(of: "\n", with: " "),
                        reading.initials]
                   })
    }

    private static func equipment(_ page: PDFCanvas, readings: [Reading]) {
        let stats = SafetyMath.byPoint(readings).filter { $0.outOfRange > 0 }
        guard !stats.isEmpty else { return }
        page.heading("Which equipment failed")
        page.table(headers: ["Check point", "Readings", "Outside limits", "Rate"],
                   widths: [0.46, 0.18, 0.2, 0.16],
                   rows: stats.map { ["\($0.pointName)", "\($0.recorded)", "\($0.outOfRange)", Formatters.percent($0.outOfRangeRate)] })
    }

    private static func coolingSection(_ page: PDFCanvas, records: [CoolingRecord]) {
        guard !records.isEmpty else { return }
        page.heading("Cooling log")
        page.table(headers: ["Started", "Item", "In at", "Stage 1", "Stage 2", "Result", "By"],
                   widths: [0.16, 0.2, 0.1, 0.17, 0.17, 0.12, 0.08],
                   rows: records.map { record in
                       [Formatters.dateTime.string(from: record.startedAt),
                        record.displayItem,
                        record.temperature(record.startTemp),
                        stageCell(at: record.stageOneAt, temp: record.stageOneTemp, record: record),
                        stageCell(at: record.stageTwoAt, temp: record.stageTwoTemp, record: record),
                        SafetyMath.evaluate(record).name,
                        record.initials]
                   })
        let failed = records.filter { SafetyMath.evaluate($0) == .failed && !$0.correctiveAction.isEmpty }
        if !failed.isEmpty {
            page.table(headers: ["Batch", "Corrective action"],
                       widths: [0.3, 0.7],
                       rows: failed.map { [$0.displayItem, $0.correctiveAction.replacingOccurrences(of: "\n", with: " ")] })
        }
    }

    private static func log(_ page: PDFCanvas, readings: [Reading]) {
        guard !readings.isEmpty else { return }
        page.heading("Every reading")
        page.table(headers: ["When", "Check point", "Slot", "Reading", "Limit", "In range", "By"],
                   widths: [0.18, 0.22, 0.12, 0.12, 0.16, 0.12, 0.08],
                   rows: readings.map { reading in
                       [Formatters.dateTime.string(from: reading.date),
                        reading.pointName,
                        reading.slot.name,
                        reading.valueText,
                        limitCell(reading),
                        reading.isInRange ? "Yes" : "No",
                        reading.initials]
                   })
    }

    // MARK: Cells

    private static func limitCell(_ reading: Reading) -> String {
        let suffix = reading.kind.isChemical ? " ppm" : " \(reading.unit.rawValue)"
        switch (reading.minLimit, reading.maxLimit) {
        case let (min?, max?): return "\(Formatters.amount(min))-\(Formatters.amount(max))\(suffix)"
        case let (nil, max?):  return "≤ \(Formatters.amount(max))\(suffix)"
        case let (min?, nil):  return "≥ \(Formatters.amount(min))\(suffix)"
        default:               return "—"
        }
    }

    private static func stageCell(at: Date?, temp: Double?, record: CoolingRecord) -> String {
        guard let at, let temp else { return "not recorded" }
        return "\(Formatters.time.string(from: at)) · \(record.temperature(temp))"
    }
}
