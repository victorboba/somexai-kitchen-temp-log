import SwiftUI
import SwiftData

/// Batches on the clock, and the ones already finished today.
struct CoolingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Location.createdAt) private var locations: [Location]
    @Query(sort: \CoolingRecord.startedAt, order: .reverse) private var records: [CoolingRecord]

    @AppStorage("app.locationID") private var storedLocationID = ""
    @State private var starting = false
    @State private var now = Date.now

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var isWide: Bool { horizontalSizeClass == .regular }
    private var location: Location? {
        locations.first { $0.id.uuidString == storedLocationID } ?? locations.first
    }
    private var mine: [CoolingRecord] { records.filter { $0.locationID == location?.id } }
    private var active: [CoolingRecord] { SafetyMath.active(mine) }
    private var finished: [CoolingRecord] {
        mine.filter { SafetyMath.evaluate($0) != .running }.prefix(30).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if location == nil {
                    ContentUnavailableView("Nothing to cool yet", systemImage: "timer",
                                           description: Text("Add a location on the Today tab first."))
                } else if mine.isEmpty {
                    ContentUnavailableView {
                        Label("No cooling batches", systemImage: "timer")
                    } description: {
                        Text("Start a batch when hot food goes into the cooler. The app runs the two checkpoints you set and asks for the temperature at each.")
                    } actions: {
                        Button("Start a Batch") { starting = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if !active.isEmpty {
                            Section("On the clock") {
                                ForEach(active) { record in
                                    NavigationLink { CoolingDetailView(record: record) } label: {
                                        CoolingRow(record: record, now: now)
                                    }
                                }
                            }
                        }
                        if !finished.isEmpty {
                            Section("Finished") {
                                ForEach(finished) { record in
                                    NavigationLink { CoolingDetailView(record: record) } label: {
                                        CoolingRow(record: record, now: now)
                                    }
                                }
                                .onDelete(perform: delete)
                            }
                        }
                        Section { Text(AppConfig.disclaimer).font(.footnote).foregroundStyle(.secondary) }
                    }
                    .maxContentWidth(isWide ? 760 : .infinity)
                }
            }
            .navigationTitle("Cooling")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { starting = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Start a batch")
                        .disabled(location == nil)
                }
            }
            .sheet(isPresented: $starting) {
                if let location { CoolingStartView(location: location) }
            }
            .onReceive(tick) { now = $0 }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let record = finished[index]
            CheckReminder.cancelCooling(record)
            context.delete(record)
        }
    }
}

/// Start a batch: what it is, what it went in at, and the two checkpoints (prefilled from Setup).
struct CoolingStartView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let location: Location

    @AppStorage("cooling.stageOneTarget") private var stageOneTarget = 70.0
    @AppStorage("cooling.stageOneMinutes") private var stageOneMinutes = 120
    @AppStorage("cooling.stageTwoTarget") private var stageTwoTarget = 41.0
    @AppStorage("cooling.stageTwoMinutes") private var stageTwoMinutes = 360
    @AppStorage("entry.initials") private var initials = ""

    @State private var item = ""
    @State private var batchSize = ""
    @State private var startTempText = ""
    @FocusState private var itemFocused: Bool

    private var startTemp: Double? { Double(startTempText.replacingOccurrences(of: ",", with: ".")) }
    private var canStart: Bool { startTemp != nil && !item.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("What is cooling") {
                    TextField("Chili, rice, stock…", text: $item).focused($itemFocused)
                    TextField("Batch size, optional", text: $batchSize)
                }
                Section {
                    HStack {
                        TextField("0", text: $startTempText)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(location.unit.rawValue).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Temperature going in")
                }
                Section {
                    LabeledContent("Stage 1",
                                   value: "\(Formatters.amount(stageOneTarget)) \(location.unit.rawValue) within \(Formatters.minutes(stageOneMinutes))")
                    LabeledContent("Stage 2",
                                   value: "\(Formatters.amount(stageTwoTarget)) \(location.unit.rawValue) within \(Formatters.minutes(stageTwoMinutes))")
                    NavigationLink("Change the checkpoints") { CoolingSettingsView(unit: location.unit) }
                } header: {
                    Text("Your checkpoints")
                } footer: {
                    Text("These are the numbers you entered in Setup. The app runs your clock and records what the thermometer says.")
                }
                Section("Who") {
                    TextField("Initials", text: $initials)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Start a Batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }.fontWeight(.semibold).disabled(!canStart)
                }
            }
            .onAppear { itemFocused = true }
        }
    }

    private func start() {
        guard let startTemp else { return }
        let record = CoolingRecord(locationID: location.id,
                                   item: item.trimmingCharacters(in: .whitespacesAndNewlines),
                                   startTemp: startTemp, unit: location.unit,
                                   stageOneTarget: stageOneTarget, stageOneMinutes: stageOneMinutes,
                                   stageTwoTarget: stageTwoTarget, stageTwoMinutes: stageTwoMinutes)
        record.batchSize = batchSize.trimmingCharacters(in: .whitespacesAndNewlines)
        record.initials = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(record)
        try? context.save()
        Task { await CheckReminder.scheduleCooling(record) }
        dismiss()
    }
}

/// The checkpoints, kept in one place because they are the same for every batch in a kitchen.
struct CoolingSettingsView: View {
    let unit: TempUnit

    @AppStorage("cooling.stageOneTarget") private var stageOneTarget = 70.0
    @AppStorage("cooling.stageOneMinutes") private var stageOneMinutes = 120
    @AppStorage("cooling.stageTwoTarget") private var stageTwoTarget = 41.0
    @AppStorage("cooling.stageTwoMinutes") private var stageTwoMinutes = 360

    var body: some View {
        Form {
            Section {
                Stepper("Down to \(Formatters.amount(stageOneTarget)) \(unit.rawValue)",
                        value: $stageOneTarget, in: -20...200, step: 1)
                Stepper("Within \(Formatters.minutes(stageOneMinutes))",
                        value: $stageOneMinutes, in: 15...600, step: 15)
            } header: {
                Text("Stage 1")
            }
            Section {
                Stepper("Down to \(Formatters.amount(stageTwoTarget)) \(unit.rawValue)",
                        value: $stageTwoTarget, in: -20...200, step: 1)
                Stepper("Within \(Formatters.minutes(stageTwoMinutes)) of starting",
                        value: $stageTwoMinutes, in: 30...1440, step: 30)
            } header: {
                Text("Stage 2")
            } footer: {
                Text("Enter the checkpoints your own health department enforces. Temp Log runs the clock and compares the readings; it does not know your local code.")
            }
        }
        .navigationTitle("Cooling Checkpoints")
        .navigationBarTitleDisplayMode(.inline)
    }
}
