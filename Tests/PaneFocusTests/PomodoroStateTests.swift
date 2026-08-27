// Unit tests for the pomodoro engine.
//
// `PomodoroState` is deliberately free of AppKit, SwiftUI and NotchCore, so all of this is
// pure arithmetic against an injected instant. Nothing here waits on a real clock.

import Foundation
import XCTest

@testable import PaneFocus

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private let minute: TimeInterval = 60
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func state(
    work: Int = 25,
    rest: Int = 5,
    autoAdvance: Bool = false,
    phase: FocusPhase = .work
) -> PomodoroState {
    PomodoroState(
        settings: FocusSettings(workMinutes: work, breakMinutes: rest, autoAdvance: autoAdvance),
        phase: phase
    )
}

// MARK: - Countdown arithmetic

final class PomodoroCountdownTests: XCTestCase {

    func testAStoppedPhaseShowsItsFullDuration() {
        let s = state()
        XCTAssertEqual(s.remaining(at: t0), 25 * minute)
        XCTAssertEqual(s.elapsed(at: t0), 0)
        XCTAssertEqual(s.progress(at: t0), 0)
    }

    func testRemainingIsDerivedFromTheDeadlineNotAccumulated() {
        var s = state()
        s.start(at: t0)
        XCTAssertEqual(s.remaining(at: t0 + 10 * minute), 15 * minute)
        XCTAssertEqual(s.elapsed(at: t0 + 10 * minute), 10 * minute)
    }

    func testProgressRunsZeroToOneAndClamps() {
        var s = state()
        s.start(at: t0)
        XCTAssertEqual(s.progress(at: t0), 0, accuracy: 0.0001)
        XCTAssertEqual(s.progress(at: t0 + 12.5 * minute), 0.5, accuracy: 0.0001)
        XCTAssertEqual(s.progress(at: t0 + 25 * minute), 1, accuracy: 0.0001)
        // Past the deadline but not yet caught up.
        XCTAssertEqual(s.progress(at: t0 + 40 * minute), 1, accuracy: 0.0001)
    }

    func testRemainingNeverGoesNegative() {
        var s = state()
        s.start(at: t0)
        XCTAssertEqual(s.remaining(at: t0 + 90 * minute), 0)
    }

    func testPausingHoldsTheRemainingTimeStill() {
        var s = state()
        s.start(at: t0)
        s.pause(at: t0 + 10 * minute)
        XCTAssertEqual(s.remaining(at: t0 + 10 * minute), 15 * minute)
        // An hour later it is still holding the same 15 minutes.
        XCTAssertEqual(s.remaining(at: t0 + 70 * minute), 15 * minute)
    }

    func testResumingCountsFromWhenItResumed() {
        var s = state()
        s.start(at: t0)
        s.pause(at: t0 + 10 * minute)
        s.start(at: t0 + 60 * minute)
        XCTAssertEqual(s.remaining(at: t0 + 60 * minute), 15 * minute)
        XCTAssertEqual(s.remaining(at: t0 + 65 * minute), 10 * minute)
    }

    func testStartingAnAlreadyRunningPhaseIsANoOp() {
        var s = state()
        s.start(at: t0)
        let before = s.run
        s.start(at: t0 + 5 * minute)
        XCTAssertEqual(s.run, before)
    }
}

// MARK: - The span the idle notch counts down against

final class PomodoroSpanTests: XCTestCase {

    func testOnlyARunningPhaseHasASpan() {
        var s = state()
        XCTAssertNil(s.span)

        s.start(at: t0)
        XCTAssertNotNil(s.span)

        s.pause(at: t0 + minute)
        XCTAssertNil(s.span, "a held countdown has nothing for the shell to advance")

        s.reset()
        XCTAssertNil(s.span)
    }

    func testTheSpanCoversExactlyThePhaseDuration() throws {
        var s = state()
        s.start(at: t0)
        let span = try XCTUnwrap(s.span)
        XCTAssertEqual(span.lowerBound, t0)
        XCTAssertEqual(span.upperBound, t0 + 25 * minute)
    }

    /// The shell derives the arc from the span alone, so the two have to agree at every
    /// instant or the idle ring and the pane would disagree about the same session.
    func testProgressDerivedFromTheSpanMatchesTheState() throws {
        var s = state()
        s.start(at: t0)
        s.pause(at: t0 + 10 * minute)
        s.start(at: t0 + 60 * minute)

        let span = try XCTUnwrap(s.span)
        let total = span.upperBound.timeIntervalSince(span.lowerBound)

        for offset in stride(from: 0.0, through: 15 * minute, by: 30) {
            let instant = t0 + 60 * minute + offset
            let fromSpan = instant.timeIntervalSince(span.lowerBound) / total
            XCTAssertEqual(fromSpan, s.progress(at: instant), accuracy: 0.0001)
        }
    }

    func testTheSpanFollowsAClockJump() throws {
        var s = state()
        s.start(at: t0)
        s.shiftDeadline(by: 30 * minute)
        let span = try XCTUnwrap(s.span)
        XCTAssertEqual(span.upperBound, t0 + 55 * minute)
        XCTAssertEqual(span.lowerBound, t0 + 30 * minute)
    }
}

// MARK: - Boundaries

final class PomodoroBoundaryTests: XCTestCase {

    func testCrossingTheDeadlineCountsTheRoundAndMovesToABreak() {
        var s = state()
        s.start(at: t0)
        let events = s.catchUp(at: t0 + 25 * minute, calendar: utc)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.finished, .work)
        XCTAssertEqual(events.first?.next, .rest)
        XCTAssertEqual(events.first?.roundsToday, 1)
        XCTAssertEqual(s.phase, .rest)
        XCTAssertEqual(s.rounds(at: t0 + 25 * minute, calendar: utc), 1)
    }

    func testFinishingABreakCountsNothing() {
        var s = state(phase: .rest)
        s.start(at: t0)
        s.catchUp(at: t0 + 5 * minute, calendar: utc)
        XCTAssertEqual(s.phase, .work)
        XCTAssertEqual(s.rounds(at: t0 + 5 * minute, calendar: utc), 0)
    }

    func testCompletionReportsWhenItActuallyFinishedNotWhenItWasNoticed() {
        var s = state()
        s.start(at: t0)
        // The lid was shut; we only look two hours later.
        let events = s.catchUp(at: t0 + 120 * minute, calendar: utc)
        XCTAssertEqual(events.first?.finishedAt, t0 + 25 * minute)
    }

    func testWithoutAutoAdvanceOneBoundaryIsAppliedAndItStops() {
        var s = state()
        s.start(at: t0)
        let events = s.catchUp(at: t0 + 120 * minute, calendar: utc)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(s.run, .idle)
    }

    func testAutoAdvanceChainsFromTheDeadlineNotFromNow() {
        var s = state(work: 25, rest: 5, autoAdvance: true)
        s.start(at: t0)

        // 25 work, then 5 break, then 25 work: boundaries at 25, 30 and 55 minutes.
        // Chaining from `now` instead of from each deadline would drag every one of these
        // later by however long the app went unwatched.
        let events = s.catchUp(at: t0 + 58 * minute, calendar: utc)

        XCTAssertEqual(events.map(\.finishedAt), [
            t0 + 25 * minute,
            t0 + 30 * minute,
            t0 + 55 * minute,
        ])
        XCTAssertEqual(s.phase, .rest)
        XCTAssertEqual(s.remaining(at: t0 + 58 * minute), 2 * minute)
        XCTAssertEqual(s.rounds(at: t0 + 58 * minute, calendar: utc), 2)
    }

    /// The boundary is `deadline <= now`, so a phase ending on the exact instant it is
    /// sampled counts as crossed rather than sitting there finished but unapplied.
    func testABoundaryLandingOnTheSampledInstantIsCrossed() {
        var s = state()
        s.start(at: t0)
        XCTAssertEqual(s.catchUp(at: t0 + 25 * minute, calendar: utc).count, 1)
    }

    func testCatchUpIsBoundedRatherThanLoopingForever() {
        var s = state(work: 1, rest: 1, autoAdvance: true)
        s.start(at: t0)
        let events = s.catchUp(at: t0 + 10_000 * minute, limit: 8, calendar: utc)
        XCTAssertEqual(events.count, 8)
        XCTAssertEqual(s.run, .idle, "left stopped rather than holding a deadline in the past")
    }

    func testAPausedPhaseIsNeverCrossedByCatchUp() {
        var s = state()
        s.start(at: t0)
        s.pause(at: t0 + minute)
        XCTAssertTrue(s.catchUp(at: t0 + 500 * minute, calendar: utc).isEmpty)
        XCTAssertEqual(s.phase, .work)
    }
}

// MARK: - Rounds

final class PomodoroRoundTests: XCTestCase {

    private func finishRounds(_ count: Int, from start: Date, into s: inout PomodoroState) {
        var now = start
        for _ in 0..<count {
            s.phase = .work
            s.start(at: now)
            now += 25 * minute
            s.catchUp(at: now, calendar: utc)
        }
    }

    func testRoundsAccumulateThroughTheDay() {
        var s = state()
        finishRounds(3, from: t0, into: &s)
        XCTAssertEqual(s.rounds(at: t0 + 4 * 60 * minute, calendar: utc), 3)
    }

    func testTheCountBelongsToTheDayTheRoundFinishedOn() {
        var s = state()
        finishRounds(2, from: t0, into: &s)
        let tomorrow = utc.date(byAdding: .day, value: 1, to: t0)!
        XCTAssertEqual(s.rounds(at: tomorrow, calendar: utc), 0, "yesterday's rounds are not today's")

        finishRounds(1, from: tomorrow, into: &s)
        XCTAssertEqual(s.rounds(at: tomorrow + 60 * minute, calendar: utc), 1, "a new day starts the count over")
    }

    func testARoundThatEndsAfterMidnightCountsForTheNewDay() {
        let nearMidnight = utc.startOfDay(for: t0) + 24 * 60 * minute - 10 * minute
        var s = state()
        s.start(at: nearMidnight)
        s.catchUp(at: nearMidnight + 25 * minute, calendar: utc)
        XCTAssertEqual(s.rounds(at: nearMidnight + 25 * minute, calendar: utc), 1)
        XCTAssertEqual(s.rounds(at: nearMidnight, calendar: utc), 0)
    }
}

// MARK: - Transport

final class PomodoroTransportTests: XCTestCase {

    func testSkippingAFocusRoundDoesNotCountIt() {
        var s = state()
        s.start(at: t0)
        s.skip(at: t0 + minute)
        XCTAssertEqual(s.phase, .rest)
        XCTAssertEqual(s.rounds(at: t0 + minute, calendar: utc), 0, "it was skipped, not worked")
    }

    func testSkippingABreakGoesBackToFocus() {
        var s = state(phase: .rest)
        s.skip(at: t0)
        XCTAssertEqual(s.phase, .work)
    }

    func testSkippingAStoppedTimerDoesNotStartTheNextPhase() {
        var s = state(autoAdvance: true)
        s.skip(at: t0)
        XCTAssertEqual(s.run, .idle)
    }

    func testSkippingARunningTimerCarriesTheRunningStateOverWhenAutoAdvanceIsOn() {
        var s = state(autoAdvance: true)
        s.start(at: t0)
        s.skip(at: t0 + minute)
        XCTAssertTrue(s.isRunning)
        XCTAssertEqual(s.remaining(at: t0 + minute), 5 * minute)
    }

    func testResetReturnsToFullDurationWithoutErasingTheRounds() {
        var s = state()
        s.start(at: t0)
        s.catchUp(at: t0 + 25 * minute, calendar: utc)
        s.phase = .work
        s.start(at: t0 + 30 * minute)
        s.reset()
        XCTAssertEqual(s.run, .idle)
        XCTAssertEqual(s.remaining(at: t0 + 40 * minute), 25 * minute)
        XCTAssertEqual(s.rounds(at: t0 + 40 * minute, calendar: utc), 1)
    }

    func testToggleStartsThenPauses() {
        var s = state()
        s.toggle(at: t0)
        XCTAssertTrue(s.isRunning)
        s.toggle(at: t0 + minute)
        XCTAssertTrue(s.isPaused)
        XCTAssertFalse(s.isRunning)
    }

    func testIsActiveCoversRunningAndPausedButNotStopped() {
        var s = state()
        XCTAssertFalse(s.isActive)
        s.start(at: t0)
        XCTAssertTrue(s.isActive)
        s.pause(at: t0 + minute)
        XCTAssertTrue(s.isActive, "a held session still owns the permanent idle slot")
        s.reset()
        XCTAssertFalse(s.isActive)
    }
}

// MARK: - Clock changes

final class PomodoroClockTests: XCTestCase {

    func testShiftingTheDeadlineKeepsTheDurationTheUserAskedFor() {
        var s = state()
        s.start(at: t0)
        // The user set the clock forward an hour ten minutes in.
        s.shiftDeadline(by: 60 * minute)
        XCTAssertEqual(s.remaining(at: t0 + 70 * minute), 15 * minute)
    }

    func testShiftingDoesNothingToAStoppedOrPausedPhase() {
        var s = state()
        s.shiftDeadline(by: 60 * minute)
        XCTAssertEqual(s.run, .idle)

        s.start(at: t0)
        s.pause(at: t0 + minute)
        let held = s.run
        s.shiftDeadline(by: 60 * minute)
        XCTAssertEqual(s.run, held)
    }
}

// MARK: - Settings

final class FocusSettingsTests: XCTestCase {

    func testDurationsAreClampedToTheirAllowedRange() {
        let s = FocusSettings(workMinutes: 500, breakMinutes: 0)
        XCTAssertEqual(s.workMinutes, 90)
        XCTAssertEqual(s.breakMinutes, 1)
    }

    func testAdjustStopsAtTheEdgeRatherThanWrapping() {
        var s = FocusSettings(workMinutes: 90)
        s.adjust(.work, by: 5)
        XCTAssertEqual(s.workMinutes, 90)
        XCTAssertFalse(s.canAdjust(.work, by: 1))
        XCTAssertTrue(s.canAdjust(.work, by: -1))
    }

    func testStateWrittenByAnOlderBuildStillRestores() throws {
        // Only two fields present, as an earlier schema would have written it.
        let json = Data(#"{"workMinutes":30,"autoAdvance":true}"#.utf8)
        let restored = try JSONDecoder().decode(FocusSettings.self, from: json)
        XCTAssertEqual(restored.workMinutes, 30)
        XCTAssertTrue(restored.autoAdvance)
        XCTAssertEqual(restored.breakMinutes, 5, "missing fields fall back to the defaults")
    }

    func testTheCycleEraBreakBecomesTheBreak() throws {
        let json = Data(#"{"workMinutes":25,"shortBreakMinutes":7,"longBreakMinutes":20,"sessionsPerCycle":4}"#.utf8)
        let restored = try JSONDecoder().decode(FocusSettings.self, from: json)
        XCTAssertEqual(restored.breakMinutes, 7)
    }

    func testACycleEraStateRestoresItsPhaseAndSettings() throws {
        let json = Data(#"""
        {"settings":{"workMinutes":30,"shortBreakMinutes":6,"longBreakMinutes":15,"sessionsPerCycle":4,"autoAdvance":false},
         "phase":"longBreak","completedInCycle":4,"run":{"idle":{}}}
        """#.utf8)
        let restored = try JSONDecoder().decode(PomodoroState.self, from: json)
        XCTAssertEqual(restored.phase, .rest, "a long break is a break")
        XCTAssertEqual(restored.settings.workMinutes, 30)
        XCTAssertEqual(restored.settings.breakMinutes, 6)
        XCTAssertEqual(restored.rounds(at: t0, calendar: utc), 0)
    }

    func testNonsenseOnDiskIsClampedRatherThanThrown() throws {
        let json = Data(#"{"workMinutes":100000,"breakMinutes":-3}"#.utf8)
        let restored = try JSONDecoder().decode(FocusSettings.self, from: json)
        XCTAssertEqual(restored.workMinutes, 90)
        XCTAssertEqual(restored.breakMinutes, 1)
    }

    func testAStateRoundTripsThroughCoding() throws {
        var s = state(work: 40, autoAdvance: true)
        s.start(at: t0)
        s.catchUp(at: t0 + 40 * minute, calendar: utc)
        let restored = try JSONDecoder().decode(
            PomodoroState.self, from: JSONEncoder().encode(s)
        )
        XCTAssertEqual(restored, s)
    }
}
