import Foundation

enum Formatters {
    static let dateTime: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
    static let date: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
    static let time: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()
    /// "Sep 16"
    static let short: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    /// "Wed, Sep 16"
    static let weekdayShort: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    /// "38" / "38.5", trimming trailing zeros.
    static func amount(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        let s = String(format: "%.1f", value)
        return s.replacingOccurrences(of: "\\.0$", with: "", options: .regularExpression)
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    /// "1 hr 20 min" / "45 min", the long units the owner asked for.
    static func minutes(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    /// "1 hr 20 min left" / "35 min over", from a signed second count.
    static func countdown(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        let text = minutes == 0 ? "under a minute" : Self.minutes(minutes)
        return seconds >= 0 ? "\(text) left" : "\(text) over"
    }
}
