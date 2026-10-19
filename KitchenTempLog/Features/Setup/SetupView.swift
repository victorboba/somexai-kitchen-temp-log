import SwiftUI
import SwiftData

/// Everything that is configured once: the location, the check points, the cooling checkpoints
/// and the reminders.
struct SetupView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Location.createdAt) private var locations: [Location]
    @Query(sort: \LogPoint.sortIndex) private var points: [LogPoint]

    @AppStorage("app.locationID") private var storedLocationID = ""
    @AppStorage(CheckReminder.enabledKey) private var remindersOn = false

    private var location: Location? {
        locations.first { $0.id.uuidString == storedLocationID } ?? locations.first
    }
    private var myPoints: [LogPoint] {
        points.filter { $0.locationID == location?.id && !$0.archived }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("This kitchen") {
                    NavigationLink {
                        LocationListView(selectedID: $storedLocationID)
                    } label: {
                        LabeledContent("Location", value: location?.displayName ?? "None yet")
                    }
                    if let location {
                        LabeledContent("Scale", value: location.unit.name)
                        LabeledContent("Opens at", value: hourText(location.openingHour))
                    }
                }

                Section {
                    NavigationLink {
                        PointListView()
                    } label: {
                        LabeledContent("Check points", value: "\(myPoints.count)")
                    }
                    ForEach(Slot.allCases) { slot in
                        let count = myPoints.filter { $0.slots.contains(slot) }.count
                        LabeledContent(slot.name, value: count == 1 ? "1 check" : "\(count) checks")
                    }
                } header: {
                    Text("The shift list")
                } footer: {
                    Text("Every check point on every slot it is ticked for becomes one line on the Today tab.")
                }

                Section {
                    NavigationLink("Cooling checkpoints") {
                        CoolingSettingsView(unit: location?.unit ?? .fahrenheit)
                    }
                } header: {
                    Text("Cooling")
                }

                Section {
                    Toggle("Remind me at each slot", isOn: $remindersOn)
                        .onChange(of: remindersOn) { _, _ in reschedule() }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text(location.map { "Opening at \(hourText($0.openingHour)), midday at \(hourText($0.openingHour + Slot.midday.hourOffset)), closing at \(hourText($0.openingHour + Slot.closing.hourOffset)). A cooling batch also alerts ten minutes before each checkpoint." }
                         ?? "Add a location to set the times.")
                }

                Section {
                    Text(AppConfig.disclaimer).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Setup")
        }
    }

    private func hourText(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour % 24
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? .now
        return Formatters.time.string(from: date)
    }

    private func reschedule() {
        let current = location
        let scheduled = myPoints
        Task { await CheckReminder.reschedule(location: current, points: scheduled) }
    }
}

struct LocationListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Location.createdAt) private var locations: [Location]

    @Binding var selectedID: String
    @State private var editing: Location?
    @State private var creating = false

    var body: some View {
        List {
            ForEach(locations) { location in
                Button {
                    selectedID = location.id.uuidString
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.displayName).font(.body.weight(.semibold))
                            Text(location.unit.name + (location.licenseNumber.isEmpty ? "" : " · permit \(location.licenseNumber)"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if location.id.uuidString == selectedID {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                        Button { editing = location } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Edit \(location.displayName)")
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Locations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add location")
            }
        }
        .sheet(isPresented: $creating) { LocationEditorView(location: nil, selectedID: $selectedID) }
        .sheet(item: $editing) { LocationEditorView(location: $0, selectedID: $selectedID) }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let location = locations[index]
            if location.id.uuidString == selectedID { selectedID = "" }
            context.delete(location)
        }
    }
}

struct LocationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let location: Location?
    @Binding var selectedID: String

    @State private var name = ""
    @State private var licenseNumber = ""
    @State private var manager = ""
    @State private var unit: TempUnit = .fahrenheit
    @State private var openingHour = 7

    var body: some View {
        NavigationStack {
            Form {
                Section("The kitchen") {
                    TextField("Front Kitchen, Truck 2…", text: $name)
                    Picker("Scale", selection: $unit) {
                        ForEach(TempUnit.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Opens at", selection: $openingHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(hourText(hour)).tag(hour)
                        }
                    }
                } header: {
                    Text("Hours")
                } footer: {
                    Text("The slot reminders are hung off this hour: opening, five hours later, and ten hours later.")
                }
                Section {
                    TextField("Permit or licence number", text: $licenseNumber)
                    TextField("Person in charge", text: $manager)
                } header: {
                    Text("For the printed log")
                } footer: {
                    Text("Both are optional and both are printed at the top of the inspector PDF.")
                }
            }
            .navigationTitle(location == nil ? "New Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let location else { return }
                name = location.name
                licenseNumber = location.licenseNumber
                manager = location.manager
                unit = location.unit
                openingHour = location.openingHour
            }
        }
    }

    private func hourText(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? .now
        return Formatters.time.string(from: date)
    }

    private func save() {
        let target = location ?? Location()
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.licenseNumber = licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        target.manager = manager.trimmingCharacters(in: .whitespacesAndNewlines)
        target.unit = unit
        target.openingHour = openingHour
        if location == nil {
            context.insert(target)
            selectedID = target.id.uuidString
        }
        try? context.save()
        dismiss()
    }
}
