import XCTest
import PDFKit
@testable import KitchenTempLog

final class ExportTests: XCTestCase {
    private let calendar = Calendar.current

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        let midnight = calendar.startOfDay(for: .now)
        let shifted = calendar.date(byAdding: .day, value: -offset, to: midnight)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: shifted)!
    }

    private func sample() -> (Location, [LogPoint], [Reading], [CoolingRecord]) {
        let location = Location(name: "Front Kitchen", unit: .fahrenheit)
        location.licenseNumber = "FS-2026-4471"

        let walkIn = LogPoint(locationID: location.id, name: "Walk-in cooler", kind: .cold,
                              minLimit: nil, maxLimit: 41, slots: [.opening, .closing])
        let well = LogPoint(locationID: location.id, name: "Hot well", kind: .hot,
                            minLimit: 135, maxLimit: nil, slots: [.midday])

        let good = Reading(point: walkIn, slot: .opening, value: 38, unit: .fahrenheit, date: day(1))
        good.initials = "RA"
        let bad = Reading(point: walkIn, slot: .closing, value: 47, unit: .fahrenheit, date: day(1, hour: 20))
        bad.correctiveAction = "Moved product to the reach-in"
        bad.initials = "JM"
        let cold = Reading(point: well, slot: .midday, value: 120, unit: .fahrenheit, date: day(0, hour: 13))

        let batch = CoolingRecord(locationID: location.id, item: "Chili", startTemp: 180, unit: .fahrenheit,
                                  stageOneTarget: 70, stageOneMinutes: 120,
                                  stageTwoTarget: 41, stageTwoMinutes: 360,
                                  startedAt: day(1, hour: 14))
        batch.stageOneAt = batch.startedAt.addingTimeInterval(90 * 60)
        batch.stageOneTemp = 64
        batch.stageTwoAt = batch.startedAt.addingTimeInterval(300 * 60)
        batch.stageTwoTemp = 39
        batch.stage = SafetyMath.evaluate(batch)

        return (location, [walkIn, well], [good, bad, cold], [batch])
    }

    /// PDFDocument wraps text at the column width, so every phrase must be compared with whitespace collapsed.
    private func text(of url: URL) throws -> String {
        let document = try XCTUnwrap(PDFDocument(url: url))
        let raw = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: " ")
        return raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // MARK: CSV

    func testReadingsCSVHasOneRowPerReadingPlusTheHeader() {
        let (location, _, readings, _) = sample()
        let csv = CSVExporter.readingsCSV(readings, locationName: location.displayName)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(String(lines[0]), CSVExporter.readingHeader)
        XCTAssertTrue(csv.contains("\"Walk-in cooler\""))
        XCTAssertTrue(csv.contains("\"Moved product to the reach-in\""))
    }

    func testCSVRecordsWhetherEachReadingWasInRange() {
        let (location, _, readings, _) = sample()
        let csv = CSVExporter.readingsCSV(readings, locationName: location.displayName)
        XCTAssertEqual(csv.components(separatedBy: "\"yes\"").count - 1, 1)
        XCTAssertEqual(csv.components(separatedBy: "\"no\"").count - 1, 2)
    }

    func testCSVQuotesEscapeEmbeddedQuotes() {
        let location = Location(name: "Truck \"2\"")
        let point = LogPoint(locationID: location.id, name: "Cooler", kind: .cold, minLimit: nil, maxLimit: 41)
        let reading = Reading(point: point, slot: .opening, value: 38, unit: .fahrenheit)
        let csv = CSVExporter.readingsCSV([reading], locationName: location.displayName)
        XCTAssertTrue(csv.contains("\"Truck \"\"2\"\"\""))
    }

    func testCoolingCSVCarriesBothStagesAndTheResult() {
        let (location, _, _, cooling) = sample()
        let csv = CSVExporter.coolingCSV(cooling, locationName: location.displayName)
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
        XCTAssertTrue(csv.contains("\"Chili\""))
        XCTAssertTrue(csv.contains("\"Passed\""))
    }

    // MARK: PDF

    func testPDFCarriesTheSummaryTheLimitsAndEveryReading() throws {
        let (location, points, readings, cooling) = sample()
        let url = try ReportExporter.export(location: location, points: points, readings: readings,
                                            cooling: cooling, from: day(6), to: .now, periodLabel: "7 days")
        let body = try text(of: url)
        XCTAssertTrue(body.contains("Food Safety Temperature Log"))
        XCTAssertTrue(body.contains("Front Kitchen"))
        XCTAssertTrue(body.contains("FS-2026-4471"))
        XCTAssertTrue(body.contains("Checks recorded"))
        XCTAssertTrue(body.contains("Walk-in cooler"))
        XCTAssertTrue(body.contains("Hot well"))
        try? FileManager.default.removeItem(at: url)
    }

    func testPDFPrintsTheCorrectiveActionAgainstEachFailure() throws {
        let (location, points, readings, cooling) = sample()
        let url = try ReportExporter.export(location: location, points: points, readings: readings,
                                            cooling: cooling, from: day(6), to: .now, periodLabel: "7 days")
        let body = try text(of: url)
        XCTAssertTrue(body.contains("Outside limits, and what was done"))
        XCTAssertTrue(body.contains("Moved product to the reach-in"))
        try? FileManager.default.removeItem(at: url)
    }

    /// A failure with nothing written against it has to stand out, not disappear.
    func testPDFFlagsAFailureWithNoCorrectiveAction() throws {
        let (location, points, readings, cooling) = sample()
        let url = try ReportExporter.export(location: location, points: points, readings: readings,
                                            cooling: cooling, from: day(6), to: .now, periodLabel: "7 days")
        XCTAssertTrue(try text(of: url).contains("NOT RECORDED"))
        try? FileManager.default.removeItem(at: url)
    }

    func testPDFSaysTheOperatorSetTheLimits() throws {
        let (location, points, readings, cooling) = sample()
        let url = try ReportExporter.export(location: location, points: points, readings: readings,
                                            cooling: cooling, from: day(6), to: .now, periodLabel: "7 days")
        XCTAssertTrue(try text(of: url).contains("You set every limit"))
        try? FileManager.default.removeItem(at: url)
    }

    func testPDFSurvivesAnEmptyPeriod() throws {
        let location = Location(name: "Truck 2")
        let url = try ReportExporter.export(location: location, points: [], readings: [], cooling: [],
                                            from: day(6), to: .now, periodLabel: "7 days")
        XCTAssertTrue(try text(of: url).contains("Summary"))
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Formatting

    func testLimitTextReadsLikeAClipboard() {
        let cooler = LogPoint(locationID: UUID(), name: "Walk-in", kind: .cold, minLimit: nil, maxLimit: 41)
        XCTAssertEqual(cooler.limitText(.fahrenheit), "41 °F or below")
        let well = LogPoint(locationID: UUID(), name: "Well", kind: .hot, minLimit: 135, maxLimit: nil)
        XCTAssertEqual(well.limitText(.fahrenheit), "135 °F or above")
        let bucket = LogPoint(locationID: UUID(), name: "Bucket", kind: .sanitizer, minLimit: 200, maxLimit: 400)
        XCTAssertEqual(bucket.limitText(.fahrenheit), "200 to 400 ppm")
    }

    func testCountdownReadsForwardsAndBackwards() {
        XCTAssertEqual(Formatters.countdown(5400), "1 hr 30 min left")
        XCTAssertEqual(Formatters.countdown(-1800), "30 min over")
        XCTAssertEqual(Formatters.countdown(30), "under a minute left")
    }

    func testAmountTrimsTrailingZeros() {
        XCTAssertEqual(Formatters.amount(38), "38")
        XCTAssertEqual(Formatters.amount(38.5), "38.5")
        XCTAssertEqual(Formatters.amount(-6), "-6")
    }
}
