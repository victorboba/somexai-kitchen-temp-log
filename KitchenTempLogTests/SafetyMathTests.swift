import XCTest
@testable import KitchenTempLog

final class SafetyMathTests: XCTestCase {
    private let site = UUID()
    private let other = UUID()
    private let calendar = Calendar.current

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        let midnight = calendar.startOfDay(for: .now)
        let shifted = calendar.date(byAdding: .day, value: -offset, to: midnight)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: shifted)!
    }

    private func point(_ name: String = "Walk-in", kind: PointKind = .cold,
                       min: Double? = nil, max: Double? = 41,
                       slots: [Slot] = [.opening, .closing], locationID: UUID? = nil) -> LogPoint {
        LogPoint(locationID: locationID ?? site, name: name, kind: kind, minLimit: min, maxLimit: max, slots: slots)
    }

    private func reading(_ point: LogPoint, _ value: Double, slot: Slot = .opening,
                         offset: Int = 0, hour: Int = 9, action: String = "") -> Reading {
        let r = Reading(point: point, slot: slot, value: value, unit: .fahrenheit, date: day(offset, hour: hour))
        r.correctiveAction = action
        return r
    }

    // MARK: Limits

    func testColdReadingUnderTheCeilingIsInRange() {
        XCTAssertTrue(reading(point(), 38).isInRange)
    }

    func testColdReadingOverTheCeilingIsOut() {
        XCTAssertFalse(reading(point(), 45).isInRange)
    }

    func testAReadingExactlyOnTheLimitPasses() {
        XCTAssertTrue(reading(point(max: 41), 41).isInRange)
        XCTAssertTrue(reading(point(kind: .hot, min: 135, max: nil), 135).isInRange)
    }

    func testHotHoldingUsesAFloorNotACeiling() {
        let well = point("Hot well", kind: .hot, min: 135, max: nil)
        XCTAssertFalse(reading(well, 120).isInRange)
        XCTAssertTrue(reading(well, 160).isInRange)
    }

    func testSanitiserUsesBothEnds() {
        let bucket = point("Bucket", kind: .sanitizer, min: 200, max: 400)
        XCTAssertFalse(reading(bucket, 150).isInRange)
        XCTAssertTrue(reading(bucket, 300).isInRange)
        XCTAssertFalse(reading(bucket, 450).isInRange)
    }

    /// The limits are snapshotted onto the reading, so raising a limit today does not
    /// silently turn last week's failures into passes.
    func testEditingAPointDoesNotRewriteOldReadings() {
        let walkIn = point(max: 41)
        let old = reading(walkIn, 45)
        walkIn.maxLimit = 50
        XCTAssertFalse(old.isInRange)
    }

    func testSuggestedLimitsFollowTheScale() {
        XCTAssertEqual(PointKind.cold.suggestedLimits(.fahrenheit).max, 41)
        XCTAssertEqual(PointKind.cold.suggestedLimits(.celsius).max, 5)
        XCTAssertNil(PointKind.hot.suggestedLimits(.fahrenheit).max)
    }

    // MARK: The shift list

    func testExpectedIsOneLinePerPointPerSlot() {
        let points = [point("A", slots: [.opening, .closing]), point("B", slots: [.midday])]
        XCTAssertEqual(SafetyMath.expected(points).count, 3)
    }

    func testArchivedPointsLeaveTheShiftList() {
        let live = point("A", slots: [.opening])
        let gone = point("B", slots: [.opening])
        gone.archived = true
        XCTAssertEqual(SafetyMath.expected([live, gone]).count, 1)
    }

    func testOutstandingDropsSlotsThatHaveAReading() {
        let walkIn = point(slots: [.opening, .closing])
        let taken = [reading(walkIn, 38, slot: .opening)]
        let due = SafetyMath.outstanding([walkIn], readings: taken, on: .now)
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.slot, .closing)
    }

    func testAReadingOnlySatisfiesItsOwnSlot() {
        let walkIn = point(slots: [.opening, .closing])
        let taken = [reading(walkIn, 38, slot: .closing)]
        XCTAssertNil(SafetyMath.reading(for: .init(pointID: walkIn.id, slot: .opening), in: taken, on: .now))
    }

    func testYesterdaysReadingDoesNotSatisfyToday() {
        let walkIn = point(slots: [.opening])
        let taken = [reading(walkIn, 38, offset: 1)]
        XCTAssertEqual(SafetyMath.outstanding([walkIn], readings: taken, on: .now).count, 1)
    }

    // MARK: Summary

    func testSummaryCountsRangeAndMissingActions() {
        let walkIn = point(slots: [.opening])
        let readings = [
            reading(walkIn, 38),
            reading(walkIn, 45, offset: 1, action: "Moved product"),
            reading(walkIn, 46, offset: 2),
        ]
        let s = SafetyMath.summary([walkIn], readings: readings, from: day(2), to: day(0))
        XCTAssertEqual(s.recorded, 3)
        XCTAssertEqual(s.inRange, 1)
        XCTAssertEqual(s.outOfRange, 2)
        XCTAssertEqual(s.missingCorrectiveAction, 1)
    }

    func testExpectedScalesWithTheDaysInTheRange() {
        let walkIn = point(slots: [.opening, .closing])
        let s = SafetyMath.summary([walkIn], readings: [], from: day(4), to: day(0))
        XCTAssertEqual(s.expected, 10)
        XCTAssertEqual(s.completionRate, 0)
    }

    func testDayCountIncludesBothEnds() {
        XCTAssertEqual(SafetyMath.dayCount(from: day(6), to: day(0)), 7)
        XCTAssertEqual(SafetyMath.dayCount(from: day(0), to: day(0)), 1)
    }

    func testSummaryOfNothingDoesNotDivideByZero() {
        let s = SafetyMath.summary([], readings: [], from: day(1), to: day(0))
        XCTAssertEqual(s.completionRate, 0)
        XCTAssertEqual(s.inRangeRate, 0)
    }

    // MARK: Filtering and series

    func testReadingsAreFilteredByLocation() {
        let mine = point()
        let theirs = point(locationID: other)
        let all = [reading(mine, 38), reading(theirs, 38)]
        XCTAssertEqual(SafetyMath.readings(all, at: site).count, 1)
    }

    func testDailySeriesHasOneEntryPerDayIncludingEmptyOnes() {
        let walkIn = point()
        let readings = [reading(walkIn, 38), reading(walkIn, 45, offset: 3)]
        let series = SafetyMath.dailySeries(readings, from: day(3), to: day(0))
        XCTAssertEqual(series.count, 4)
        XCTAssertEqual(series.first?.outOfRange, 1)
        XCTAssertEqual(series[1].recorded, 0)
        XCTAssertEqual(series.last?.recorded, 1)
    }

    func testEquipmentIsRankedByFailuresFirst() {
        let good = point("Good")
        let bad = point("Bad")
        let readings = [reading(good, 38), reading(bad, 45), reading(bad, 46), reading(bad, 38)]
        let stats = SafetyMath.byPoint(readings)
        XCTAssertEqual(stats.first?.pointName, "Bad")
        XCTAssertEqual(stats.first?.outOfRange, 2)
        XCTAssertEqual(stats.first?.recorded, 3)
    }

    // MARK: Cooling

    private func batch(startedMinutesAgo: Int = 0) -> CoolingRecord {
        CoolingRecord(locationID: site, item: "Chili", startTemp: 180, unit: .fahrenheit,
                      stageOneTarget: 70, stageOneMinutes: 120,
                      stageTwoTarget: 41, stageTwoMinutes: 360,
                      startedAt: Date().addingTimeInterval(TimeInterval(-startedMinutesAgo * 60)))
    }

    func testABatchWithNoReadingsIsStillRunning() {
        XCTAssertEqual(SafetyMath.evaluate(batch()), .running)
    }

    func testBothStagesOnTimeAndOnTargetPasses() {
        let record = batch(startedMinutesAgo: 400)
        record.stageOneAt = record.startedAt.addingTimeInterval(90 * 60)
        record.stageOneTemp = 65
        record.stageTwoAt = record.startedAt.addingTimeInterval(300 * 60)
        record.stageTwoTemp = 38
        XCTAssertEqual(SafetyMath.evaluate(record), .passed)
    }

    /// The right temperature recorded after the checkpoint is still a failure, which is how the rule works.
    func testStageOneRecordedLateFailsEvenAtTheRightTemperature() {
        let record = batch(startedMinutesAgo: 400)
        record.stageOneAt = record.startedAt.addingTimeInterval(150 * 60)
        record.stageOneTemp = 60
        XCTAssertEqual(SafetyMath.evaluate(record), .failed)
    }

    func testStageOneOnTimeButTooWarmFails() {
        let record = batch(startedMinutesAgo: 400)
        record.stageOneAt = record.startedAt.addingTimeInterval(100 * 60)
        record.stageOneTemp = 85
        XCTAssertEqual(SafetyMath.evaluate(record), .failed)
    }

    func testStageTwoIsMeasuredFromTheStartNotFromStageOne() {
        let record = batch(startedMinutesAgo: 500)
        record.stageOneAt = record.startedAt.addingTimeInterval(60 * 60)
        record.stageOneTemp = 65
        record.stageTwoAt = record.startedAt.addingTimeInterval(400 * 60)
        record.stageTwoTemp = 38
        XCTAssertEqual(SafetyMath.evaluate(record), .failed)
    }

    func testADiscardedBatchStaysDiscarded() {
        let record = batch()
        record.stage = .discarded
        XCTAssertEqual(SafetyMath.evaluate(record), .discarded)
    }

    func testActiveListsOnlyRunningBatchesOldestFirst() {
        let running = batch(startedMinutesAgo: 30)
        let older = batch(startedMinutesAgo: 90)
        let done = batch(startedMinutesAgo: 400)
        done.stageOneAt = done.startedAt.addingTimeInterval(60 * 60)
        done.stageOneTemp = 65
        done.stageTwoAt = done.startedAt.addingTimeInterval(300 * 60)
        done.stageTwoTemp = 38
        let active = SafetyMath.active([running, older, done])
        XCTAssertEqual(active.count, 2)
        XCTAssertEqual(active.first?.id, older.id)
    }

    func testTheNextDeadlineMovesToStageTwoOnceStageOneIsIn() {
        let record = batch(startedMinutesAgo: 60)
        XCTAssertEqual(record.nextDeadline, record.stageOneDeadline)
        record.stageOneAt = .now
        record.stageOneTemp = 65
        XCTAssertEqual(record.nextDeadline, record.stageTwoDeadline)
        record.stageTwoAt = .now
        record.stageTwoTemp = 38
        XCTAssertNil(record.nextDeadline)
    }

    func testSecondsToDeadlineGoesNegativeOnceItIsPast() {
        let record = batch(startedMinutesAgo: 150)
        let seconds = SafetyMath.secondsToDeadline(record, now: .now)
        XCTAssertNotNil(seconds)
        XCTAssertLessThan(seconds ?? 0, 0)
    }
}
