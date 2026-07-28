import Foundation
import NotchCore
import SwiftUI

/// The expanded pomodoro.
///
/// The countdown is redrawn by a `TimelineView` on a schedule that stops producing entries
/// when the pane is not on screen, so closing the notch stops the ticking without swapping
/// any view out for another one.
struct FocusPaneContent: View {
    let pane: FocusPane

    var body: some View {
        TimelineView(CountdownSchedule(isTicking: pane.isVisible && pane.state.isRunning)) { context in
            body(at: context.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paneInsets()
    }

    private func body(at instant: Date) -> some View {
        VStack(spacing: FocusLayout.stackSpacing) {
            HStack(spacing: FocusLayout.columnSpacing) {
                dial(at: instant)
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DurationBar(pane: pane)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Dial

    private func dial(at instant: Date) -> some View {
        let remaining = pane.state.remaining(at: instant)
        let clock = notchTime(remaining)

        return ZStack {
            NotchRing(
                value: pane.state.progress(at: instant),
                size: FocusLayout.ringSize,
                lineWidth: FocusLayout.ringWidth,
                tint: Style.focusAccent
            )

            Text(clock)
                .font(Style.numericLarge)
                .foregroundStyle(pane.state.isActive ? Style.ink : Style.inkMuted)
                .contentTransition(.numericText(countsDown: true))
                .notchAnimation(Motion.tap, value: clock)
                .notchAnimation(Motion.content, value: pane.state.isActive)
        }
        .overlay { halo }
        .scaleEffect(pane.state.isRunning ? 1 : FocusLayout.restingDialScale)
        .notchAnimation(Motion.content, value: pane.state.isRunning)
    }

    /// The completion flourish. One ring swells out of the dial and fades, which reads at
    /// the edge of vision without demanding the eye the way a flash would.
    private var halo: some View {
        Circle()
            .stroke(Style.focusAccent, lineWidth: FocusLayout.ringWidth)
            .phaseAnimator(FlourishPhase.allCases, trigger: pane.flourishToken) { view, phase in
                view
                    .scaleEffect(phase.scale)
                    .opacity(phase.opacity)
            } animation: { _ in
                Motion.reduced(Motion.content)
            }
            .allowsHitTesting(false)
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: FocusLayout.detailSpacing) {
            HStack(spacing: FocusLayout.dotSpacing * 2) {
                Text(pane.state.phase.title)
                    .font(Style.title)
                    .foregroundStyle(Style.ink)
                    .notchAnimation(Motion.content, value: pane.state.phase)

                SessionDots(state: pane.state)
            }

            NotchLabel("Session \(pane.state.sessionIndex) of \(pane.state.settings.sessionsPerCycle)")

            HStack(spacing: FocusLayout.controlSpacing) {
                NotchButton(pane.state.isRunning ? "pause.fill" : "play.fill", size: FocusLayout.primaryControl) {
                    pane.toggle()
                }
                .accessibilityLabel(pane.state.isRunning ? "Pause" : "Start")

                NotchButton("forward.end.fill", size: FocusLayout.secondaryControl) { pane.skip() }
                    .accessibilityLabel("Skip phase")

                NotchButton("arrow.counterclockwise", size: FocusLayout.secondaryControl) { pane.reset() }
                    .accessibilityLabel("Reset phase")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Session dots

/// Completed, current and upcoming sessions in the cycle. The current one is a pill; when
/// it completes the pill narrows into a dot and the next one widens, so the row moves
/// rather than redrawing.
private struct SessionDots: View {
    let state: PomodoroState

    var body: some View {
        HStack(spacing: FocusLayout.dotSpacing) {
            ForEach(0..<state.settings.sessionsPerCycle, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: width(for: index), height: FocusLayout.dotSize)
            }
        }
        .notchAnimation(Motion.content, value: state.completedInCycle)
        .notchAnimation(Motion.content, value: state.phase)
        .accessibilityLabel("\(state.completedInCycle) of \(state.settings.sessionsPerCycle) sessions complete")
    }

    private var currentIndex: Int? {
        state.phase == .work ? min(state.completedInCycle, state.settings.sessionsPerCycle - 1) : nil
    }

    private func fill(for index: Int) -> Color {
        if index < state.completedInCycle { return Style.focusAccent }
        if index == currentIndex { return Style.focusAccent.opacity(0.75) }
        return Style.hairline
    }

    private func width(for index: Int) -> CGFloat {
        index == currentIndex ? FocusLayout.dotSize * 2.6 : FocusLayout.dotSize
    }
}

// MARK: - Durations

/// Durations and auto-advance, in the pane. There is no settings window to open, because
/// leaving the notch to change 25 into 30 would be absurd.
private struct DurationBar: View {
    let pane: FocusPane

    var body: some View {
        HStack(spacing: FocusLayout.controlSpacing) {
            ForEach(FocusPhase.allCases, id: \.self) { phase in
                DurationStepper(pane: pane, phase: phase)
            }

            Spacer(minLength: 0)

            AutoAdvanceChip(pane: pane)
        }
    }
}

private struct DurationStepper: View {
    let pane: FocusPane
    let phase: FocusPhase

    var body: some View {
        NotchTile(interactive: false) {
            HStack(spacing: FocusLayout.stepperSpacing) {
                Image(systemName: phase.symbol)
                    .font(Style.numeric)
                    .foregroundStyle(phase == pane.state.phase ? Style.focusAccent : Style.inkFaint)
                    .notchAnimation(Motion.content, value: pane.state.phase)

                NotchButton("minus", size: FocusLayout.stepperControl) { pane.adjust(phase, by: -1) }
                    .accessibilityLabel("Shorten \(phase.shortTitle)")

                Text("\(pane.state.settings.minutes(for: phase))")
                    .font(Style.numeric)
                    .foregroundStyle(Style.ink)
                    .frame(width: FocusLayout.stepperValueWidth)
                    .contentTransition(.numericText())
                    .notchAnimation(Motion.tap, value: pane.state.settings.minutes(for: phase))

                NotchButton("plus", size: FocusLayout.stepperControl) { pane.adjust(phase, by: 1) }
                    .accessibilityLabel("Lengthen \(phase.shortTitle)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(phase.shortTitle) minutes")
    }
}

private struct AutoAdvanceChip: View {
    let pane: FocusPane

    private var isOn: Bool { pane.state.settings.autoAdvance }

    var body: some View {
        NotchTile {
            HStack(spacing: FocusLayout.stepperSpacing) {
                Circle()
                    .fill(isOn ? Style.focusAccent : Style.hairline)
                    .frame(width: FocusLayout.dotSize, height: FocusLayout.dotSize)
                    .scaleEffect(isOn ? 1 : FocusLayout.restingDotScale)

                NotchLabel("Auto")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { pane.setAutoAdvance(!isOn) }
        .notchAnimation(Motion.tap, value: isOn)
        .accessibilityLabel("Auto advance")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Schedule

/// A 1Hz schedule that produces nothing once the pane is off screen.
///
/// A countdown needs one redraw per second and not one more. Driving it from a schedule
/// rather than a timer means the notch closing genuinely stops the work, and the ring still
/// sweeps between entries because `NotchRing` animates the value it is handed.
private struct CountdownSchedule: TimelineSchedule {
    let isTicking: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard isTicking else {
            return AnyIterator([startDate].makeIterator())
        }

        let step: TimeInterval = mode == .lowFrequency ? 60 : 1
        var next = startDate
        return AnyIterator {
            let entry = next
            // Snap to the boundary so the digits change with the second, not with whenever
            // the view happened to be built.
            let aligned = (entry.timeIntervalSinceReferenceDate / step).rounded(.down) * step + step
            next = Date(timeIntervalSinceReferenceDate: aligned)
            if next <= entry { next = entry.addingTimeInterval(step) }
            return entry
        }
    }
}

// MARK: - Flourish

/// Invisible, then a ring at the dial's edge, then that ring swollen and gone.
private enum FlourishPhase: CaseIterable {
    case rest, bloom, spent

    var scale: Double {
        switch self {
        case .rest, .bloom: 1
        case .spent:        1.26
        }
    }

    var opacity: Double {
        switch self {
        case .rest, .spent: 0
        case .bloom:        0.5
        }
    }
}

// MARK: - Layout

/// Sizes local to this pane's composition. Everything shared lives in `Metrics`.
private enum FocusLayout {
    static let ringSize: CGFloat = 82
    static let ringWidth: CGFloat = 7
    static let restingDialScale: Double = 0.97

    static let stackSpacing: CGFloat = 8
    static let columnSpacing: CGFloat = 18
    static let detailSpacing: CGFloat = 6
    static let controlSpacing: CGFloat = 6
    static let stepperSpacing: CGFloat = 3

    static let dotSize: CGFloat = 6
    static let dotSpacing: CGFloat = 4
    static let restingDotScale: Double = 0.7

    static let primaryControl: CGFloat = 17
    static let secondaryControl: CGFloat = 12
    static let stepperControl: CGFloat = 8
    static let stepperValueWidth: CGFloat = 18
}
