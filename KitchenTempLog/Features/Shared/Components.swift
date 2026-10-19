import SwiftUI

/// Keeps a column of content readable on an iPad without changing anything on a phone.
struct MaxContentWidth: ViewModifier {
    var width: CGFloat
    func body(content: Content) -> some View {
        content.frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

extension View {
    func maxContentWidth(_ width: CGFloat = 660) -> some View { modifier(MaxContentWidth(width: width)) }
}

extension PointKind {
    /// Cold kinds read blue, hot kinds read red, so a glance at the list sorts them without reading.
    var tint: Color {
        switch self {
        case .cold, .receiving: return .blue
        case .frozen: return .cyan
        case .hot, .cooking: return .red
        case .sanitizer: return .purple
        case .ambient: return .gray
        }
    }
}

/// A rounded, grouped-background panel.
struct Panel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// One line of the shift list: the check point, its limit, and either the reading or a prompt.
struct DueRow: View {
    let point: LogPoint
    let slot: Slot
    let reading: Reading?
    let unit: TempUnit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: point.kind.symbol)
                .font(.title3)
                .foregroundStyle(point.kind.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(point.displayName).font(.body.weight(.semibold)).lineLimit(1)
                Text(point.limitText(unit)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let reading {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(reading.valueText)
                        .font(.body.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(reading.isInRange ? Color.green : Color.red)
                    Text(Formatters.time.string(from: reading.date))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: reading.isInRange ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(reading.isInRange ? Color.green : Color.red)
            } else {
                Text("Tap to log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A labelled figure, used across the Today and Log screens.
struct StatBlock: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One cooling batch, with the live countdown to whichever checkpoint is next.
struct CoolingRow: View {
    let record: CoolingRecord
    let now: Date

    private var stage: CoolingStage { SafetyMath.evaluate(record) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stage.symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayItem).font(.body.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if stage == .running, let seconds = SafetyMath.secondsToDeadline(record, now: now) {
                Text(Formatters.countdown(seconds))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(seconds < 0 ? Color.red : seconds < 900 ? Color.orange : Color.secondary)
            } else {
                Text(stage.name).font(.caption.weight(.semibold)).foregroundStyle(color)
            }
        }
        .contentShape(Rectangle())
    }

    private var color: Color {
        switch stage {
        case .running: return .accentColor
        case .passed: return .green
        case .failed: return .red
        case .discarded: return .secondary
        }
    }

    private var detail: String {
        var parts = ["In at \(record.temperature(record.startTemp))"]
        if record.stageOneAt == nil {
            parts.append("stage 1 by \(Formatters.time.string(from: record.stageOneDeadline))")
        } else if record.stageTwoAt == nil {
            parts.append("stage 2 by \(Formatters.time.string(from: record.stageTwoDeadline))")
        } else if let temp = record.stageTwoTemp {
            parts.append("finished at \(record.temperature(temp))")
        }
        return parts.joined(separator: " · ")
    }
}

/// One historical reading in the Log list.
struct ReadingRow: View {
    let reading: Reading

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reading.isInRange ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(reading.isInRange ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.pointName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(reading.valueText).font(.subheadline.weight(.bold)).monospacedDigit()
                Text(Formatters.time.string(from: reading.date)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts = [reading.slot.name]
        if !reading.initials.isEmpty { parts.append(reading.initials) }
        if !reading.correctiveAction.isEmpty { parts.append(reading.correctiveAction) }
        else if !reading.notes.isEmpty { parts.append(reading.notes) }
        return parts.joined(separator: " · ")
    }
}
