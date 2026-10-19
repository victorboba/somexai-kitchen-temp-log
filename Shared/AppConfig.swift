import Foundation

/// Everything user-facing that changes per app. Compiled into both the app and the widget,
/// so keep it free of UIKit/SwiftUI imports.
enum AppConfig {
    // MARK: Identity
    static let appName = "Temp Log"
    static let storeName = "Kitchen Temp Log"
    static let bundleID = "com.example.kitchen-temp-log"
    static let appGroupID = "group.com.example.kitchen-temp-log"
    /// Your App Store ID once the app is live. The Rate button stays hidden while it is empty.
    static let appStoreID = ""

    // MARK: Sync
    static let iCloudSyncEnabled = false

    // MARK: StoreKit
    static let productPrefix = bundleID.replacingOccurrences(of: "-", with: "")
    static let annualProductID = "\(productPrefix).pro.annual"
    static let lifetimeProductID = "\(productPrefix).pro.lifetime"

    // MARK: Links
    static let supportEmail = "support@somexai.com"
    static let privacyPolicyURL = URL(string: "https://somexai.com/privacy/kitchen-temp-log/")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    // MARK: Copy
    static let entryNoun = "Reading"
    static let entryNounPlural = "Readings"
    static let exportFileStem = "temp-log"

    /// The boundary. The app runs the operator's own limits and clocks; it does not know the code.
    static let disclaimer = """
    You set every limit and every cooling checkpoint in this app, to match what your own health \
    department enforces. Temp Log compares your readings against those numbers and keeps the record. \
    It is not a food-safety authority and does not replace your HACCP plan or your inspector.
    """

    static let onboarding: [OnboardingPage] = [
        OnboardingPage(symbol: "list.bullet.rectangle.portrait.fill", title: "The shift list",
                       body: "Opening, midday and closing checks in one list. Tap a line, type the number, done."),
        OnboardingPage(symbol: "exclamationmark.triangle.fill", title: "Out of range asks why",
                       body: "A reading past your limit will not save until you write what you did about it. That is the part inspectors read."),
        OnboardingPage(symbol: "doc.text.fill", title: "The log the inspector wants",
                       body: "A PDF for any date range, with every reading, every cooling batch and every corrective action."),
    ]

    static let paywallSymbol = "thermometer.variable.and.figure"
    static let paywallHeadline = "Unlock Temp Log"
    static let paywallBenefits = [
        "Unlimited check points, readings and locations",
        "Two-stage cooling logs with checkpoint alerts",
        "Corrective actions recorded against every failure",
        "Inspector PDF and CSV for any date range",
        "No account, no server, nothing leaves the device",
    ]

    // MARK: How-to guide
    static let howToIntro = "Five steps from install to the log an inspector can read. Each takes under a minute."
    static let howTo: [HowToStep] = [
        HowToStep(symbol: "building.2", title: "Name the kitchen",
                  body: "On the Setup tab tap Locations, add the kitchen or truck, and choose Fahrenheit or Celsius. Add your permit number if you want it printed on the log.",
                  tip: "Run more than one site by adding a location for each. Check points and readings stay separate."),
        HowToStep(symbol: "thermometer.medium", title: "Add your check points",
                  body: "Setup → Check Points → +. Name the walk-in, pick the kind, and set the limits your health department enforces. Common numbers are offered; change them to yours.",
                  tip: "Tick the slots each point is due in: opening, midday, closing."),
        HowToStep(symbol: "checklist", title: "Work the shift list",
                  body: "The Today tab lists what is due. Tap a line, type the reading, tap Save. Green means inside your limits.",
                  tip: "A reading outside the limits opens the corrective action box and will not save empty."),
        HowToStep(symbol: "timer", title: "Start a cooling batch",
                  body: "Cooling → Start a Batch. Name the food and enter the temperature it went in at. The app counts down to each checkpoint you set and asks for the temperature at both.",
                  tip: "Turn on reminders in Setup and the phone tells you when a checkpoint is close."),
        HowToStep(symbol: "square.and.arrow.up", title: "Print the log",
                  body: "The Log tab has the history. Pick a date range and tap PDF for the inspector, or export CSV for your own records."),
        HowToStep(symbol: "rectangle.on.rectangle", title: "Add the widget",
                  body: "Long-press your Home Screen, tap +, search \"Temp Log\", and add the widget to see what is still due today."),
    ]

    /// Display prices used only by DEBUG screenshot runs (`-mockPrices`).
    static let mockPrices = (annual: "$19.99", lifetime: "$49.99")

    // MARK: Behaviour
    static let reviewAfterSuccesses = 8
}

struct HowToStep: Identifiable, Hashable {
    var id: String { title }
    let symbol: String
    let title: String
    let body: String
    var tip: String? = nil
}

struct OnboardingPage: Identifiable, Hashable {
    var id: String { title }
    let symbol: String
    let title: String
    let body: String
}
