# Temp Log (Kitchen Temp Log)

A food-safety temperature log for a small kitchen: shift checks, two-stage cooling on a clock, and a PDF an inspector can read. It is for owners and cooks of small restaurants, trucks, cafes and daycares. It runs on iPhone and iPad.

One of a set of niche iPhone apps built from a shared SwiftUI template. It was never released on the App Store; the code is here for anyone to use. The template is [somexai-ios-template](https://github.com/victorboba/somexai-ios-template) and the collection is [somexai-ios-apps](https://github.com/victorboba/somexai-ios-apps).

## What it does

- Locations: a kitchen, a truck or a cart, with permit number and person in charge printed on the log.
- Check points: cold holding, frozen, hot holding, cooking, receiving, sanitizer and room, each with your own limits and the shift slots it is due in.
- Today: the shift list grouped by Opening, Midday and Closing, with the day's totals on top.
- Out-of-range readings ask why: the corrective action box opens and Save stays disabled until it has text. Four one-tap answers per kind cover most cases.
- Cooling: two-stage batches with a live countdown, a notification ten minutes before each checkpoint, and a temperature entry at both. A checkpoint recorded late fails even at the right temperature.
- Log: 7, 30 or 90 days or all, with completion rate, a chart of in and out of range, every failure, and which equipment failed most.
- Export: an inspector PDF plus CSVs for readings and cooling.
- Slot reminders, a widget, a Siri App Shortcut and a How-to guide.

## The boundary

The app does not know your local code. Every limit and both cooling checkpoints are entered by you; common numbers are offered when a check point is created and you confirm or change them. The app compares readings against those numbers and keeps the record. It is not a food-safety authority and does not replace your HACCP plan or your inspector. The disclaimer appears on Today, Cooling, Log, Setup and the foot of every export.

## Privacy

Data stays on the device in SwiftData. There is no account, no analytics and no network access, and iCloud sync is off (`iCloudSyncEnabled = false`). Nothing leaves the phone unless you export a PDF or CSV and share it yourself.

## Model notes

- `LogPoint` covers all seven kinds; `PointKind` decides the unit, whether there is a floor, a ceiling or both, and the starting numbers offered.
- `Reading` snapshots the point's name and both limits, so renaming a walk-in or changing a limit never rewrites old logs. Deleting a point archives it for the same reason.
- `CoolingRecord` stores both checkpoints as a target plus minutes from the start, so stage 2 is measured from when the food went in.
- `SafetyMath` holds every rate, series and evaluation with no SwiftData dependency, so it is unit-tested directly.

## Build and run

- Requirements: Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), iOS 17 or later.
- Run `xcodegen generate`, open `KitchenTempLog.xcodeproj`, pick the `KitchenTempLog` scheme and an iPhone or iPad simulator, and Run.
- Tests: `xcodebuild -scheme KitchenTempLog -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' test`.
- Paywall: the app has a hard paywall (annual subscription or lifetime purchase). Running from Xcode uses the bundled `Products.storekit` file, so purchases are simulated and free. Debug builds can also skip it with the `-unlock` launch argument or the Debug switch in Settings.
- To run on your own device or ship it: set your team in `project.yml` (`DEVELOPMENT_TEAM`), change the `com.example` bundle ID prefix in `project.yml`, both `.entitlements` files and `Products.storekit`, and update `supportEmail`, `privacyPolicyURL` and `appStoreID` in `Shared/AppConfig.swift`.

## Project layout

- `KitchenTempLog/App/`, `KitchenTempLog/Core/`: app entry and root gate, StoreKit entitlement, export, review prompt, App Shortcut, widget sync.
- `KitchenTempLog/Features/`: the screens.
- `KitchenTempLog/Models/`: SwiftData models.
- `KitchenTempLog/Core/SafetyMath.swift`, `Core/Notifications/`: evaluation logic and local reminders.
- `KitchenTempLogWidget/`: the Home Screen widget, fed from a snapshot in the App Group.
- `Shared/AppConfig.swift`: everything that changes per app (name, copy, product IDs, links, How-to guide, disclaimer).
- `KitchenTempLogTests/`, `KitchenTempLogUITests/`: unit and UI tests.
- `scripts/`, `docs/`: icon and screenshot helpers, capability notes.

## License

MIT. See [LICENSE](LICENSE).
