// Unit tests for the pomodoro engine.
//
// `PomodoroState` is deliberately free of AppKit, SwiftUI and NotchCore, so all of this is
// pure arithmetic against an injected instant. Nothing here waits on a real clock.

import Foundation
import XCTest

@testable import PaneFocus

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private let minute: TimeInterval = 60

private func state(
    work: Int = 25,
    short: Int = 5,
    long: Int = 15,
    sessions: Int = 4,
    autoAdvance: Bool = false,
    phase: FocusPhase = .work,
    completed: Int = 0
) -> PomodoroState {
    PomodoroState(
        settings: FocusSettings(
            workMinutes: work,
            shortBreakMinutes: short,
            longBreakMinutes: long,
            sessionsPerCycle: sessions,
            autoAdvance: autoAdvance
        ),
        phase: phase,
        completedInCycle: completed
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

    func testCrossingTheDeadlineCreditsTheSessionAndMovesToABreak() {
        var s = state()
        s.start(at: t0)
        let events = s.catchUp(at: t0 + 25 * minute)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.finished, .work)
        XCTAssertEqual(events.first?.next, .shortBreak)
        XCTAssertEqual(s.phase, .shortBreak)
        XCTAssertEqual(s.completedInCycle, 1)
    }

    func testCompletionReportsWhenItActuallyFinishedNotWhenItWasNoticed() {
        var s = state()
        s.start(at: t0)
        // The lid was shut; we only look two hours later.
        let events = s.catchUp(at: t0 + 120 * minute)
        XCTAssertEqual(events.first?.finishedAt, t0 + 25 * minute)
    }

    func testWithoutAutoAdvanceOneBoundaryIsAppliedAndItStops() {
        var s = state()
        s.start(at: t0)
        let events = s.catchUp(at: t0 + 120 * minute)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(s.run, .idle)
    }

    func testAutoAdvanceChainsFromTheDeadlineNotFromNow() {
        var s = state(work: 25, short: 5, autoAdvance: true)
        s.start(at: t0)

        // 25 work, then 5 break, then 25 work: boundaries at 25, 30 and 55 minutes.
        // Chaining from `now` instead of from each deadline would drag every one of these
        // later by however long the app went unwatched.
        let events = s.catchUp(at: t0 + 58 * minute)

        XCTAssertEqual(events.map(\.finishedAt), [
            t0 + 25 * minute,
            t0 + 30 * minute,
            t0 + 55 * minute,
        ])
        XCTAssertEqual(s.phase, .shortBreak)
        XCTAssertEqual(s.remaining(at: t0 + 58 * minute), 2 * minute)
    }

    /// The boundary is `deadline <= now`, so a phase ending on the exact instant it is
    /// sampled counts as crossed rather than sitting there finished but unapplied.
    func testABoundaryLandingOnTheSampledInstantIsCrossed() {
        var s = state()
        s.start(at: t0)
        XCTAssertEqual(s.catchUp(at: t0 + 25 * minute).count, 1)
    }

    func testTheLongBreakArrivesOnTheLastSessionOfTheCycle() {
        var s = state(sessions: 2, autoAdvance: false, completed: 1)
        s.start(at: t0)
        s.catchUp(at: t0 + 25 * minute)
        XCTAssertEqual(s.phase, .longBreak)
        XCTAssertEqual(s.completedInCycle, 2)
    }

    func testFinishingTheLongBreakResetsTheCycle() {
        var s = state(sessions: 2, phase: .longBreak, completed: 2)
        s.start(at: t0)
        s.catchUp(at: t0 + 15 * minute)
        XCTAssertEqual(s.phase, .work)
        XCTAssertEqual(s.completedInCycle, 0)
    }

    func testCatchUpIsBoundedRatherThanLoopingForever() {
        var s = state(work: 1, short: 1, autoAdvance: true)
        s.start(at: t0)
        let events = s.catchUp(at: t0 + 10_000 * minute, limit: 8)
        XCTAssertEqual(events.count, 8)
        XCTAssertEqual(s.run, .idle, "left stopped rather than holding a deadline in the past")
    }

    func testAPausedPhaseIsNeverCrossedByCatchUp() {
        var s = state()
        s.start(at: t0)
        s.pause(at: t0 + minute)
        XCTAssertTrue(s.catchUp(at: t0 + 500 * minute).isEmpty)
        XCTAssertEqual(s.phase, .work)
    }
}

// MARK: - Transport

final class PomodoroTransportTests: XCTestCase {

    func testSkippingAWorkSessionEarnsNoCredit() {
        var s = state()
        s.start(at: t0)
        s.skip(at: t0 + minute)
        XCTAssertEqual(s.phase, .shortBreak)
        XCTAssertEqual(s.completedInCycle, 0, "it was skipped, not worked")
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

    func testResetReturnsToFullDurationWithoutErasingTheCycle() {
        var s = state(completed: 2)
        s.start(at: t0)
        s.reset()
        XCTAssertEqual(s.run, .idle)
        XCTAssertEqual(s.remaining(at: t0 + 10 * minute), 25 * minute)
        XCTAssertEqual(s.completedInCycle, 2)
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

    func testSessionIndexKeepsMeaningTheSameSessionAcrossABoundary() {
        var s = state(sessions: 4)
        XCTAssertEqual(s.sessionIndex, 1)
        s.start(at: t0)
        s.catchUp(at: t0 + 25 * minute)
        XCTAssertEqual(s.phase, .shortBreak)
        XCTAssertEqual(s.sessionIndex, 1, "the break follows session 1, it is not session 2")
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
        let s = FocusSettings(workMinutes: 500, shortBreakMinutes: 0, longBreakMinutes: -4)
        XCTAssertEqual(s.workMinutes, 90)
        XCTAssertEqual(s.shortBreakMinutes, 1)
        XCTAssertEqual(s.longBreakMinutes, 1)
    }

    func testAdjustStopsAtTheEdgeRatherThanWrapping() {
        var s = FocusSettings(workMinutes: 90)
        s.adjust(.work, by: 5)
        XCTAssertEqual(s.workMinutes, 90)
        XCTAssertFalse(s.canAdjust(.work, by: 1))
        XCTAssertTrue(s.canAdjust(.work, by: -1))
    }

    func testSessionsPerCycleIsAtLeastOne() {
        XCTAssertEqual(FocusSettings(sessionsPerCycle: 0).sessionsPerCycle, 1)
    }

    func testStateWrittenByAnOlderBuildStillRestores() throws {
        // Only two of the five fields present, as an earlier schema would have written it.
        let json = Data(#"{"workMinutes":30,"autoAdvance":true}"#.utf8)
        let restored = try JSONDecoder().decode(FocusSettings.self, from: json)
        XCTAssertEqual(restored.workMinutes, 30)
        XCTAssertTrue(restored.autoAdvance)
        XCTAssertEqual(restored.shortBreakMinutes, 5, "missing fields fall back to the defaults")
        XCTAssertEqual(restored.sessionsPerCycle, 4)
    }

    func testNonsenseOnDiskIsClampedRatherThanThrown() throws {
        let json = Data(#"{"workMinutes":100000,"sessionsPerCycle":-3}"#.utf8)
        let restored = try JSONDecoder().decode(FocusSettings.self, from: json)
        XCTAssertEqual(restored.workMinutes, 90)
        XCTAssertEqual(restored.sessionsPerCycle, 1)
    }

    func testAStateRoundTripsThroughCoding() throws {
        var s = state(work: 40, autoAdvance: true, completed: 2)
        s.start(at: t0)
        let restored = try JSONDecoder().decode(
            PomodoroState.self, from: JSONEncoder().encode(s)
        )
        XCTAssertEqual(restored, s)
    }
}
