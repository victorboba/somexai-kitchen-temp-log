import SwiftUI
import SwiftData

/// Type the number. If it falls outside the limits the operator set, the corrective action box
/// opens and Save stays disabled until something is written in it.
struct ReadingEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.requestReview) private var requestReview

    let point: LogPoint
    let slot: Slot
    let location: Location
    let reading: Reading?

    @AppStorage("entry.initials") private var initials = ""
    @State private var text = ""
    @State private var correctiveAction = ""
    @State private var notes = ""
    @FocusState private var valueFocused: Bool

    private var unit: TempUnit { location.unit }
    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }

    private var outOfRange: Bool {
        guard let value else { return false }
        if let min = point.minLimit, value < min { return true }
        if let max = point.maxLimit, value > max { return true }
        return false
    }

    private var canSave: Bool {
        guard value != nil else { return false }
        return !outOfRange || !correctiveAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: point.kind.symbol)
                            .font(.title2)
                            .foregroundStyle(point.kind.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.displayName).font(.headline)
                            Text("\(slot.name) · \(point.limitText(unit))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("0", text: $text)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .focused($valueFocused)
                        Text(point.kind.isChemical ? "ppm" : unit.rawValue)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let value {
                        Label(outOfRange ? "Outside your limit of \(point.limitText(unit))" : "Inside your limit",
                              systemImage: outOfRange ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(outOfRange ? Color.red : Color.green)
                            .accessibilityLabel(outOfRange ? "Outside the limit" : "Inside the limit")
                        .id(value)
                    }
                } header: {
                    Text("Reading")
                }

                if outOfRange {
                    Section {
                        TextField("Moved product to the walk-in, called for service…", text: $correctiveAction, axis: .vertical)
                            .lineLimit(2...5)
                        correctiveSuggestions
                    } header: {
                        Text("What did you do about it")
                    } footer: {
                        Text("An out-of-range reading will not save without this. It is the line an inspector reads first.")
                    }
                }

                Section("Who and anything else") {
                    TextField("Initials", text: $initials)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                }

                if reading != nil {
                    Section {
                        Button("Delete Reading", role: .destructive) {
                            if let reading { context.delete(reading) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(reading == nil ? "Log Reading" : "Edit Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!canSave)
                }
                // The number pad has no return key, so give it a way off the screen.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { valueFocused = false }
                }
            }
            .onAppear {
                if let reading {
                    text = Formatters.amount(reading.value)
                    correctiveAction = reading.correctiveAction
                    notes = reading.notes
                    if !reading.initials.isEmpty { initials = reading.initials }
                }
                valueFocused = true
            }
        }
    }

    /// The four things a kitchen actually does, so a line cook is not typing a sentence at 6 am.
    private var correctiveSuggestions: some View {
        let options: [String]
        switch point.kind {
        case .cold, .frozen, .receiving:
            options = ["Moved product to another unit", "Discarded product", "Adjusted thermostat, rechecking", "Called for service"]
        case .hot, .cooking:
            options = ["Reheated to the required temperature", "Discarded product", "Turned the unit up, rechecking", "Called for service"]
        case .sanitizer:
            options = ["Remade the solution", "Retested after remaking", "Replaced the test strips", "Called for service"]
        case .ambient:
            options = ["Adjusted the thermostat", "Called for service", "Rechecking in an hour", "Noted, no product affected"]
        }
        return ViewThatFits(in: .horizontal) {
            HStack { suggestionButtons(options) }
            VStack(alignment: .leading, spacing: 6) { suggestionButtons(options) }
        }
    }

    @ViewBuilder private func suggestionButtons(_ options: [String]) -> some View {
        ForEach(options, id: \.self) { option in
            Button(option) { correctiveAction = option }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }

    private func save() {
        guard let value else { return }
        let trimmedInitials = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: Reading
        if let reading {
            target = reading
            target.value = value
            target.minLimit = point.minLimit
            target.maxLimit = point.maxLimit
        } else {
            target = Reading(point: point, slot: slot, value: value, unit: unit)
            context.insert(target)
        }
        target.correctiveAction = correctiveAction.trimmingCharacters(in: .whitespacesAndNewlines)
        target.initials = trimmedInitials
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        ReviewPrompter.recordSuccess(request: requestReview)
        dismiss()
    }
}
