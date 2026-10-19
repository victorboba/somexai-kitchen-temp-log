import SwiftUI
import SwiftData
import Charts

/// The history and the export. This is the tab that is open when an inspector is standing there.
struct LogView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Location.createdAt) private var locations: [Location]
    @Query(sort: \LogPoint.sortIndex) private var points: [LogPoint]
    @Query(sort: \Reading.date, order: .reverse) private var readings: [Reading]
    @Query(sort: \CoolingRecord.startedAt, order: .reverse) private var cooling: [CoolingRecord]

    @AppStorage("app.locationID") private var storedLocationID = ""
    @State private var period: Period = .days7
    @State private var exportFile: ExportFile?
    @State private var exportError: String?

    enum Period: String, CaseIterable, Identifiable {
        case days7 = "7 days", days30 = "30 days", days90 = "90 days", all = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .days7: return 7
            case .days30: return 30
            case .days90: return 90
            case .all: return nil
            }
        }
    }

    private var isWide: Bool { horizontalSizeClass == .regular }
    private var location: Location? {
        locations.first { $0.id.uuidString == storedLocationID } ?? locations.first
    }
    private var myPoints: [LogPoint] { points.filter { $0.locationID == location?.id } }
    private var mine: [Reading] { readings.filter { $0.locationID == location?.id } }
    private var scoped: [Reading] { SafetyMath.readings(mine, from: start, to: .now) }
    private var scopedCooling: [CoolingRecord] {
        cooling.filter { $0.locationID == location?.id && $0.startedAt >= Calendar.current.startOfDay(for: start) }
    }
    private var series: [SafetyMath.DayStat] { SafetyMath.dailySeries(scoped, from: start, to: .now) }
    private var summary: SafetyMath.Summary {
        SafetyMath.summary(myPoints, readings: scoped, from: start, to: .now)
    }

    private var start: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if let days = period.days {
            return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        }
        if let earliest = mine.map(\.date).min() { return calendar.startOfDay(for: earliest) }
        return today
    }

    var body: some View {
        NavigationStack {
            Group {
                if let location {
                    List {
                        periodSection
                        if scoped.isEmpty {
                            Section { Text("No readings in this period.").foregroundStyle(.secondary) }
                        } else {
                            summarySection
                            chartSection
                            failureSection
                            equipmentSection
                            recentSection
                        }
                        exportSection(location)
                        Section { Text(AppConfig.disclaimer).font(.footnote).foregroundStyle(.secondary) }
                    }
                    .maxContentWidth(isWide ? 760 : .infinity)
                } else {
                    ContentUnavailableView("Nothing logged yet", systemImage: "doc.text",
                                           description: Text("Add a location on the Today tab first."))
                }
            }
            .navigationTitle("Log")
            .sheet(item: $exportFile) { ShareSheet(url: $0.url) }
            .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }

    // MARK: Sections

    private var periodSection: some View {
        Section {
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            HStack(spacing: 12) {
                StatBlock(value: "\(summary.recorded)", label: "readings")
                StatBlock(value: Formatters.percent(summary.completionRate), label: "of schedule")
                StatBlock(value: "\(summary.outOfRange)", label: "out of range",
                          tint: summary.outOfRange > 0 ? .red : .green)
            }
            LabeledContent("Within your limits", value: "\(summary.inRange) of \(summary.recorded) · \(Formatters.percent(summary.inRangeRate))")
            if summary.missingCorrectiveAction > 0 {
                LabeledContent("Failures with no corrective action", value: "\(summary.missingCorrectiveAction)")
                    .foregroundStyle(.red)
            }
            if !scopedCooling.isEmpty {
                LabeledContent("Cooling batches", value: "\(scopedCooling.count), \(scopedCooling.filter { SafetyMath.evaluate($0) == .failed }.count) out of limit")
            }
        }
    }

    private var chartSection: some View {
        Section("Readings per day") {
            Chart {
                ForEach(series) { day in
                    BarMark(x: .value("Day", day.day, unit: .day),
                            y: .value("In range", day.recorded - day.outOfRange))
                        .foregroundStyle(Color.accentColor)
                    BarMark(x: .value("Day", day.day, unit: .day),
                            y: .value("Out of range", day.outOfRange))
                        .foregroundStyle(Color.red)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 170)
            .padding(.vertical, 4)
            HStack(spacing: 16) {
                legend(.accentColor, "Within limits")
                legend(.red, "Outside limits")
            }
            .font(.caption)
        }
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 11, height: 11)
            Text(label).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var failureSection: some View {
        let failed = scoped.filter { !$0.isInRange }
        if !failed.isEmpty {
            Section {
                ForEach(failed.prefix(10)) { reading in
                    VStack(alignment: .leading, spacing: 4) {
                        ReadingRow(reading: reading)
                        Text(Formatters.weekdayShort.string(from: reading.date))
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.leading, 28)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Outside limits")
            } footer: {
                Text("Each one is printed on the inspector PDF with the corrective action you recorded.")
            }
        }
    }

    @ViewBuilder private var equipmentSection: some View {
        let stats = SafetyMath.byPoint(scoped).filter { $0.outOfRange > 0 }
        if !stats.isEmpty {
            Section {
                ForEach(stats.prefix(6)) { stat in
                    LabeledContent(stat.pointName,
                                   value: "\(stat.outOfRange) of \(stat.recorded) · \(Formatters.percent(stat.outOfRangeRate))")
                }
            } header: {
                Text("Which equipment failed")
            } footer: {
                Text("Worst first. A unit near the top of this list is the one to service.")
            }
        }
    }

    private var recentSection: some View {
        Section("Recent readings") {
            ForEach(scoped.prefix(15)) { reading in
                VStack(alignment: .leading, spacing: 3) {
                    ReadingRow(reading: reading)
                    Text(Formatters.weekdayShort.string(from: reading.date))
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func exportSection(_ location: Location) -> some View {
        Section {
            Button {
                export {
                    try ReportExporter.export(location: location, points: myPoints, readings: scoped,
                                              cooling: scopedCooling, from: start, to: .now,
                                              periodLabel: period.rawValue)
                }
            } label: { Label("PDF for the inspector", systemImage: "doc.richtext") }
            Button {
                export { try CSVExporter.write(CSVExporter.readingsCSV(scoped, locationName: location.displayName), suffix: "readings") }
            } label: { Label("Readings CSV", systemImage: "tablecells") }
            Button {
                export { try CSVExporter.write(CSVExporter.coolingCSV(scopedCooling, locationName: location.displayName), suffix: "cooling") }
            } label: { Label("Cooling CSV", systemImage: "tablecells") }
        } header: {
            Text("Export")
        } footer: {
            Text("The PDF lists the limits that were in force, every reading, every failure with what you did, and every cooling batch.")
        }
        .disabled(scoped.isEmpty && scopedCooling.isEmpty)
    }

    private func export(_ make: () throws -> URL) {
        do { exportFile = ExportFile(url: try make()) } catch { exportError = error.localizedDescription }
    }
}
