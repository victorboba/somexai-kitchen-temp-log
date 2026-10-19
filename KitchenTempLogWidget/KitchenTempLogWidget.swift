import WidgetKit
import SwiftUI

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct KitchenTempLogWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var remaining: Int { max(0, snapshot.expectedToday - snapshot.doneToday) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.locationName.isEmpty ? "Today" : snapshot.locationName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(snapshot.doneToday)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("of \(snapshot.expectedToday)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Text(remaining == 0 ? "all checks done" : remaining == 1 ? "1 check still due" : "\(remaining) checks still due")
                .font(.caption)
                .foregroundStyle(remaining == 0 ? Color.green : Color.secondary)
            if snapshot.outOfRangeToday > 0 {
                Label("\(snapshot.outOfRangeToday) out of range", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            if family != .systemSmall {
                if let next = snapshot.nextDue {
                    Divider()
                    Label("Next: \(next)", systemImage: "thermometer.medium").font(.footnote).lineLimit(1)
                }
                if snapshot.coolingActive > 0, let deadline = snapshot.coolingDeadline {
                    Label("Cooling check by \(deadline, style: .time)", systemImage: "timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct KitchenTempLogWidget: Widget {
    let kind = "KitchenTempLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            KitchenTempLogWidgetView(entry: entry)
        }
        .configurationDisplayName(AppConfig.appName)
        .description("What is still due today, and anything out of range.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct KitchenTempLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        KitchenTempLogWidget()
    }
}
