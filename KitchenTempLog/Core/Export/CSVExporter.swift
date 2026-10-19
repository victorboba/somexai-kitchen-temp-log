import Foundation

enum CSVExporter {
    static let readingHeader = "date,time,location,check_point,kind,slot,value,unit,min_limit,max_limit,in_range,corrective_action,initials,notes"
    static let coolingHeader = "started,location,item,batch_size,start_temp,unit,stage1_target,stage1_due,stage1_at,stage1_temp,stage2_target,stage2_due,stage2_at,stage2_temp,result,corrective_action,initials,notes"

    static func readingsCSV(_ readings: [Reading], locationName: String) -> String {
        var lines = [readingHeader]
        for reading in readings.sorted(by: { $0.date < $1.date }) {
            let fields = [
                Formatters.isoDay.string(from: reading.date),
                Formatters.isoTime.string(from: reading.date),
                locationName,
                reading.pointName,
                reading.kind.name,
                reading.slot.name,
                Formatters.amount(reading.value),
                reading.kind.isChemical ? "ppm" : reading.unit.rawValue,
                reading.minLimit.map(Formatters.amount) ?? "",
                reading.maxLimit.map(Formatters.amount) ?? "",
                reading.isInRange ? "yes" : "no",
                reading.correctiveAction.replacingOccurrences(of: "\n", with: " "),
                reading.initials,
                reading.notes.replacingOccurrences(of: "\n", with: " "),
            ]
            lines.append(fields.map(quote).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func coolingCSV(_ records: [CoolingRecord], locationName: String) -> String {
        var lines = [coolingHeader]
        for record in records.sorted(by: { $0.startedAt < $1.startedAt }) {
            let fields = [
                Formatters.dateTime.string(from: record.startedAt),
                locationName,
                record.displayItem,
                record.batchSize,
                Formatters.amount(record.startTemp),
                record.unit.rawValue,
                Formatters.amount(record.stageOneTarget),
                Formatters.time.string(from: record.stageOneDeadline),
                record.stageOneAt.map(Formatters.time.string(from:)) ?? "",
                record.stageOneTemp.map(Formatters.amount) ?? "",
                Formatters.amount(record.stageTwoTarget),
                Formatters.time.string(from: record.stageTwoDeadline),
                record.stageTwoAt.map(Formatters.time.string(from:)) ?? "",
                record.stageTwoTemp.map(Formatters.amount) ?? "",
                SafetyMath.evaluate(record).name,
                record.correctiveAction.replacingOccurrences(of: "\n", with: " "),
                record.initials,
                record.notes.replacingOccurrences(of: "\n", with: " "),
            ]
            lines.append(fields.map(quote).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func write(_ text: String, suffix: String) throws -> URL {
        let url = ExportFile.temporaryURL(suffix: suffix, extension: "csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func quote(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// A file URL wrapped so it can drive `.sheet(item:)`.
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }

    static func temporaryURL(suffix: String, extension ext: String) -> URL {
        let stamp = DateFormatter.fileStamp.string(from: .now)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppConfig.exportFileStem)-\(suffix)-\(stamp)")
            .appendingPathExtension(ext)
    }
}

extension DateFormatter {
    static let fileStamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"; return f
    }()
}

extension Formatters {
    static let isoDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let isoTime: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}
