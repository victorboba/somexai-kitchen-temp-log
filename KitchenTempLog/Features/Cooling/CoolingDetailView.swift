import SwiftUI
import SwiftData

/// One batch: the clock to the next checkpoint, and the two temperature entries.
struct CoolingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var record: CoolingRecord

    @State private var now = Date.now
    @State private var entering: Int?
    @State private var tempText = ""
    @State private var confirmingDiscard = false
    @FocusState private var tempFocused: Bool

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var stage: CoolingStage { SafetyMath.evaluate(record) }

    var body: some View {
        Form {
            headerSection
            stageSection(1, target: record.stageOneTarget, deadline: record.stageOneDeadline,
                         at: record.stageOneAt, temp: record.stageOneTemp,
                         enabled: record.stageOneAt == nil && stage == .running)
            stageSection(2, target: record.stageTwoTarget, deadline: record.stageTwoDeadline,
                         at: record.stageTwoAt, temp: record.stageTwoTemp,
                         enabled: record.stageOneAt != nil && record.stageTwoAt == nil && stage == .running)
            if stage == .failed {
                Section {
                    TextField("Discarded, reheated and restarted…", text: $record.correctiveAction, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("What did you do about it")
                } footer: {
                    Text("A batch that missed a checkpoint needs this line on the log.")
                }
            }
            Section("Anything else") {
                TextField("Initials", text: $record.initials)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Notes", text: $record.notes, axis: .vertical).lineLimit(1...4)
            }
            if stage == .running {
                Section {
                    Button("Discard this batch", role: .destructive) { confirmingDiscard = true }
                }
            }
            Section { Text(AppConfig.disclaimer).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle(record.displayItem)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { now = $0 }
        .sheet(item: Binding(get: { entering.map(StageTarget.init) }, set: { entering = $0?.stage })) { target in
            temperatureSheet(target.stage)
        }
        .confirmationDialog("Discard this batch?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                record.stage = .discarded
                CheckReminder.cancelCooling(record)
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The batch stays on the log, marked discarded.")
        }
    }

    private struct StageTarget: Identifiable {
        let stage: Int
        var id: Int { stage }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: stage.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(stage == .passed ? Color.green : stage == .failed ? Color.red : Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stage.name).font(.headline)
                    Text("Started \(Formatters.time.string(from: record.startedAt)) at \(record.temperature(record.startTemp))")
                        .font(.caption).foregroundStyle(.secondary)
                    if !record.batchSize.isEmpty {
                        Text(record.batchSize).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if stage == .running, let seconds = SafetyMath.secondsToDeadline(record, now: now) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Formatters.countdown(seconds))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(seconds < 0 ? Color.red : seconds < 900 ? Color.orange : Color.primary)
                    Text(record.stageOneAt == nil ? "until the stage 1 checkpoint" : "until the stage 2 checkpoint")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func stageSection(_ number: Int, target: Double, deadline: Date, at: Date?, temp: Double?, enabled: Bool) -> some View {
        Section("Stage \(number)") {
            LabeledContent("Target", value: "\(record.temperature(target)) by \(Formatters.time.string(from: deadline))")
            if let at, let temp {
                LabeledContent("Recorded", value: "\(record.temperature(temp)) at \(Formatters.time.string(from: at))")
                let late = at > deadline
                let warm = temp > target
                if late || warm {
                    Label(late && warm ? "Late and above target" : late ? "Recorded after the checkpoint" : "Above the target",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            } else if enabled {
                Button {
                    tempText = ""
                    entering = number
                } label: {
                    Label("Record the temperature", systemImage: "thermometer.medium")
                        .fontWeight(.semibold)
                }
            } else {
                Text("Not recorded").foregroundStyle(.secondary)
            }
        }
    }

    private func temperatureSheet(_ number: Int) -> some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0", text: $tempText)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .focused($tempFocused)
                        Text(record.unit.rawValue).font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Stage \(number) temperature")
                } footer: {
                    Text("Target \(record.temperature(number == 1 ? record.stageOneTarget : record.stageTwoTarget)) by \(Formatters.time.string(from: number == 1 ? record.stageOneDeadline : record.stageTwoDeadline)).")
                }
            }
            .navigationTitle("Record Stage \(number)")
            .onAppear { tempFocused = true }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { entering = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveStage(number) }
                        .fontWeight(.semibold)
                        .disabled(Double(tempText.replacingOccurrences(of: ",", with: ".")) == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { tempFocused = false }
                }
            }
        }
    }

    private func saveStage(_ number: Int) {
        guard let value = Double(tempText.replacingOccurrences(of: ",", with: ".")) else { return }
        if number == 1 {
            record.stageOneAt = .now
            record.stageOneTemp = value
        } else {
            record.stageTwoAt = .now
            record.stageTwoTemp = value
        }
        record.stage = SafetyMath.evaluate(record)
        try? context.save()
        CheckReminder.cancelCooling(record)
        if record.stage == .running {
            Task { await CheckReminder.scheduleCooling(record) }
        }
        entering = nil
    }
}
