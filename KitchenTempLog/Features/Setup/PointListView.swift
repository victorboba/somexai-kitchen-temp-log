import SwiftUI
import SwiftData

/// The check points for the current location, in the order they appear on the shift list.
struct PointListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Location.createdAt) private var locations: [Location]
    @Query(sort: \LogPoint.sortIndex) private var points: [LogPoint]

    @AppStorage("app.locationID") private var storedLocationID = ""
    @State private var editing: LogPoint?
    @State private var creating = false

    private var location: Location? {
        locations.first { $0.id.uuidString == storedLocationID } ?? locations.first
    }
    private var mine: [LogPoint] {
        points.filter { $0.locationID == location?.id && !$0.archived }
              .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    var body: some View {
        Group {
            if mine.isEmpty {
                ContentUnavailableView {
                    Label("No check points", systemImage: "thermometer.medium")
                } description: {
                    Text("Add every unit and station you write on the clipboard.")
                } actions: {
                    Button("New Check Point") { creating = true }.buttonStyle(.borderedProminent)
                        .disabled(location == nil)
                }
            } else {
                List {
                    ForEach(mine) { point in
                        Button { editing = point } label: {
                            HStack(spacing: 12) {
                                Image(systemName: point.kind.symbol)
                                    .foregroundStyle(point.kind.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(point.displayName).font(.body.weight(.semibold))
                                    Text("\(point.limitText(location?.unit ?? .fahrenheit)) · \(point.slots.map(\.name).joined(separator: ", "))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                }
                .maxContentWidth(760)
            }
        }
        .navigationTitle("Check Points")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New check point")
                    .disabled(location == nil)
            }
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        .sheet(isPresented: $creating) {
            if let location { PointEditorView(point: nil, location: location, nextIndex: mine.count) }
        }
        .sheet(item: $editing) { point in
            if let location { PointEditorView(point: point, location: location, nextIndex: point.sortIndex) }
        }
    }

    private func move(_ offsets: IndexSet, _ destination: Int) {
        var ordered = mine
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, point) in ordered.enumerated() { point.sortIndex = index }
        try? context.save()
    }

    /// Points are archived rather than deleted, so old readings keep the name they were taken under.
    private func delete(_ offsets: IndexSet) {
        for index in offsets { mine[index].archived = true }
        try? context.save()
    }
}

/// One check point: what it is, the kind, and the limits the operator's own code requires.
struct PointEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let point: LogPoint?
    let location: Location
    let nextIndex: Int

    @State private var name = ""
    @State private var kind: PointKind = .cold
    @State private var minText = ""
    @State private var maxText = ""
    @State private var slots: Set<Slot> = [.opening, .closing]
    @State private var notes = ""

    private var unitLabel: String { kind.isChemical ? "ppm" : location.unit.rawValue }

    var body: some View {
        NavigationStack {
            Form {
                Section("What is being checked") {
                    TextField("Walk-in cooler", text: $name)
                    Picker("Kind", selection: $kind) {
                        ForEach(PointKind.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                    }
                }

                Section {
                    if kind.hasLowerLimit {
                        LabeledContent("At least") {
                            HStack {
                                TextField("—", text: $minText).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                                Text(unitLabel).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if kind.hasUpperLimit {
                        LabeledContent("At most") {
                            HStack {
                                TextField("—", text: $maxText).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                                Text(unitLabel).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Use the common numbers for \(kind.name.lowercased())") { applySuggested() }
                        .font(.subheadline)
                } header: {
                    Text("Your limits")
                } footer: {
                    Text("Enter the numbers your own health department enforces. A reading outside them will ask for a corrective action.")
                }

                Section {
                    ForEach(Slot.allCases) { slot in
                        Toggle(isOn: Binding(
                            get: { slots.contains(slot) },
                            set: { on in if on { slots.insert(slot) } else { slots.remove(slot) } }
                        )) {
                            Label(slot.name, systemImage: slot.symbol)
                        }
                    }
                } header: {
                    Text("Due at")
                } footer: {
                    Text("Tick every time of day this point is checked. Each one becomes a line on the shift list.")
                }

                Section("Note") {
                    TextField("Where it is, which thermometer, anything useful", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(point == nil ? "New Check Point" : "Edit Check Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || slots.isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, _ in if point == nil { applySuggested() } }
        }
    }

    private func load() {
        guard let point else {
            applySuggested()
            return
        }
        name = point.name
        kind = point.kind
        minText = point.minLimit.map(Formatters.amount) ?? ""
        maxText = point.maxLimit.map(Formatters.amount) ?? ""
        slots = Set(point.slots)
        notes = point.notes
    }

    private func applySuggested() {
        let suggested = kind.suggestedLimits(location.unit)
        minText = suggested.min.map(Formatters.amount) ?? ""
        maxText = suggested.max.map(Formatters.amount) ?? ""
    }

    private func save() {
        let target = point ?? LogPoint(locationID: location.id)
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.kind = kind
        target.minLimit = kind.hasLowerLimit ? Double(minText.replacingOccurrences(of: ",", with: ".")) : nil
        target.maxLimit = kind.hasUpperLimit ? Double(maxText.replacingOccurrences(of: ",", with: ".")) : nil
        target.slots = Slot.allCases.filter { slots.contains($0) }
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if point == nil {
            target.sortIndex = nextIndex
            context.insert(target)
        }
        try? context.save()
        dismiss()
    }
}
