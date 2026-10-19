import SwiftUI
import SwiftData

/// Home: the shift list, grouped by slot, with the day's totals on top.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Location.createdAt) private var locations: [Location]
    @Query(sort: \LogPoint.sortIndex) private var points: [LogPoint]
    @Query(sort: \Reading.date, order: .reverse) private var readings: [Reading]
    @Query(sort: \CoolingRecord.startedAt, order: .reverse) private var cooling: [CoolingRecord]

    @AppStorage("app.locationID") private var storedLocationID = ""
    @State private var entry: EntryTarget?
    @State private var editingReading: Reading?
    @State private var showingSettings = false
    @State private var addingLocation = false

    struct EntryTarget: Identifiable {
        let point: LogPoint
        let slot: Slot
        var id: String { "\(point.id)-\(slot.rawValue)" }
    }

    private var isWide: Bool { horizontalSizeClass == .regular }
    private var location: Location? {
        locations.first { $0.id.uuidString == storedLocationID } ?? locations.first
    }
    private var myPoints: [LogPoint] {
        points.filter { $0.locationID == location?.id && !$0.archived }
              .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }
    private var myReadings: [Reading] { readings.filter { $0.locationID == location?.id } }
    private var todayReadings: [Reading] { SafetyMath.readings(myReadings, on: .now) }
    private var outstanding: [SafetyMath.Due] { SafetyMath.outstanding(myPoints, readings: myReadings, on: .now) }

    var body: some View {
        NavigationStack {
            Group {
                if location == nil {
                    emptyLocation
                } else if myPoints.isEmpty {
                    emptyPoints
                } else {
                    List {
                        summarySection
                        ForEach(Slot.allCases) { slot in
                            slotSection(slot)
                        }
                        Section { Text(AppConfig.disclaimer).font(.footnote).foregroundStyle(.secondary) }
                    }
                    .maxContentWidth(isWide ? 760 : .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar }
            .sheet(item: $entry) { target in
                if let location {
                    ReadingEntryView(point: target.point, slot: target.slot, location: location, reading: nil)
                }
            }
            .sheet(item: $editingReading) { reading in
                if let location, let point = points.first(where: { $0.id == reading.pointID }) {
                    ReadingEntryView(point: point, slot: reading.slot, location: location, reading: reading)
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $addingLocation) { LocationEditorView(location: nil, selectedID: $storedLocationID) }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-sampleData"), locations.isEmpty {
                SampleData.insert(into: context)
            }
            #endif
        }
        .onChange(of: readings.count, initial: true) { sync() }
        .onChange(of: cooling.count) { sync() }
        .onChange(of: points.count) { sync() }
        .onChange(of: locations.count, initial: true) { restore() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            WidgetSnapshot.defaults.removeObject(forKey: LogReadingIntent.pendingKey)
        }
    }

    private var title: String {
        guard let location else { return "Today" }
        return locations.count > 1 ? location.displayName : "Today"
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
            NavigationLink { HowToView() } label: { Image(systemName: "questionmark.circle") }
                .accessibilityLabel("How do I use this app")
        }
        if locations.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(locations) { candidate in
                        Button {
                            storedLocationID = candidate.id.uuidString
                        } label: {
                            Label(candidate.displayName, systemImage: candidate.id == location?.id ? "checkmark" : "building.2")
                        }
                    }
                } label: { Image(systemName: "building.2") }
                .accessibilityLabel("Choose location")
            }
        }
    }

    // MARK: Sections

    private var emptyLocation: some View {
        ContentUnavailableView {
            Label("Name the kitchen", systemImage: "building.2")
        } description: {
            Text("One location per kitchen, truck or cart. Check points and readings are kept separate for each.")
        } actions: {
            Button("Add Location") { addingLocation = true }.buttonStyle(.borderedProminent)
        }
    }

    private var emptyPoints: some View {
        ContentUnavailableView {
            Label("No check points yet", systemImage: "thermometer.medium")
        } description: {
            Text("Add the walk-in, the reach-in, the hot wells and anything else you write on the clipboard. Set the limits your health department enforces.")
        } actions: {
            NavigationLink("Add Check Points") { PointListView() }.buttonStyle(.borderedProminent)
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                StatBlock(value: "\(todayReadings.count) of \(SafetyMath.expected(myPoints).count)", label: "checks done")
                StatBlock(value: "\(outstanding.count)", label: "still due",
                          tint: outstanding.isEmpty ? .green : .primary)
                StatBlock(value: "\(todayReadings.filter { !$0.isInRange }.count)", label: "out of range",
                          tint: todayReadings.contains { !$0.isInRange } ? .red : .primary)
            }
            if let running = SafetyMath.active(cooling.filter { $0.locationID == location?.id }).first {
                NavigationLink {
                    CoolingDetailView(record: running)
                } label: {
                    Label("\(SafetyMath.active(cooling.filter { $0.locationID == location?.id }).count) batch cooling now",
                          systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                }
            }
        } header: {
            Text(Formatters.weekdayShort.string(from: .now))
        }
    }

    @ViewBuilder private func slotSection(_ slot: Slot) -> some View {
        let due = myPoints.filter { $0.slots.contains(slot) }
        if !due.isEmpty {
            Section {
                ForEach(due) { point in
                    let reading = SafetyMath.reading(for: .init(pointID: point.id, slot: slot), in: myReadings, on: .now)
                    Button {
                        if let reading { editingReading = reading } else { entry = EntryTarget(point: point, slot: slot) }
                    } label: {
                        DueRow(point: point, slot: slot, reading: reading, unit: location?.unit ?? .fahrenheit)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Label(slot.name, systemImage: slot.symbol)
            }
        }
    }

    // MARK: Behaviour

    private func restore() {
        if location == nil { storedLocationID = "" }
        else if storedLocationID.isEmpty, let location { storedLocationID = location.id.uuidString }
    }

    private func sync() {
        WidgetSync.update(location: location, points: myPoints, readings: myReadings,
                          cooling: cooling.filter { $0.locationID == location?.id })
        let current = location
        let scheduled = myPoints
        Task { await CheckReminder.reschedule(location: current, points: scheduled) }
    }
}
