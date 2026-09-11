import AppKit
import CoreGraphics

/// Interprets scrolling events as one-dimensional stack navigation gestures.
/// The state is deliberately local to one event stream; callers should keep one
/// instance for the stack panel that receives the events.
public struct StackScrollGesture {
    private enum Axis { case horizontal, vertical }

    private let threshold: CGFloat = 25
    private let axisLockThreshold: CGFloat = 3
    private let wheelThreshold: CGFloat = 0.01
    private let phaseLessGap: TimeInterval = 0.12
    private var axis: Axis?
    private var axisProbeX: CGFloat = 0
    private var axisProbeY: CGFloat = 0
    private var accumulated: CGFloat = 0
    private var physicalGesture = false
    private var emittedForPhysicalGesture = false
    private var emittedForPhaseLessBurst = false
    private var lastTimestamp: TimeInterval?

    public init() {}

    public mutating func reset() {
        axis = nil
        axisProbeX = 0
        axisProbeY = 0
        accumulated = 0
        physicalGesture = false
        emittedForPhysicalGesture = false
        emittedForPhaseLessBurst = false
        lastTimestamp = nil
    }

    /// Returns `+1` for next, `-1` for previous, or `nil` when no navigation
    /// step is warranted by this event.
    public mutating func step(
        deltaX: CGFloat, deltaY: CGFloat, precise: Bool,
        phase: NSEvent.Phase, momentumPhase: NSEvent.Phase,
        timestamp: TimeInterval
    ) -> Int? {
        // Phase transitions must be processed even when macOS supplies a zero
        // delta (common for BEGAN, ENDED, and CANCELLED events).
        if phase.contains(.began) {
            reset()
            physicalGesture = precise
        }
        if phase.contains(.cancelled) {
            reset()
            return nil
        }
        if precise && !phase.isEmpty && !physicalGesture {
            physicalGesture = true  // enter a gesture stream after BEGAN was missed
        }
        guard momentumPhase.isEmpty else { return nil }

        if !precise && phase.isEmpty {
            guard deltaX.isFinite, deltaY.isFinite else { return nil }
            return wheelStep(deltaX: deltaX, deltaY: deltaY)
        }

        guard deltaX.isFinite, deltaY.isFinite, timestamp.isFinite else {
            return finishIfNeeded(phase)
        }
        guard deltaX != 0 || deltaY != 0 else { return finishIfNeeded(phase) }

        if precise && phase.isEmpty, let lastTimestamp,
            timestamp - lastTimestamp > phaseLessGap
        {
            axis = nil
            axisProbeX = 0
            axisProbeY = 0
            accumulated = 0
            emittedForPhysicalGesture = false
            emittedForPhaseLessBurst = false
        }
        lastTimestamp = timestamp

        axisProbeX += deltaX
        axisProbeY += deltaY
        if axis == nil, max(abs(axisProbeX), abs(axisProbeY)) >= axisLockThreshold {
            axis = dominantAxis(deltaX: axisProbeX, deltaY: axisProbeY)
        }
        let selectedAxis = axis
        guard let selectedAxis else { return finishIfNeeded(phase) }
        let delta = selectedAxis == .horizontal ? deltaX : deltaY
        guard delta != 0 else { return finishIfNeeded(phase) }

        if precise && phase.isEmpty && emittedForPhaseLessBurst {
            return finishIfNeeded(phase)
        }

        // A reversal starts a fresh burst, avoiding a slow return gesture
        // cancelling the distance already accumulated in the other direction.
        if accumulated != 0, accumulated.sign != delta.sign { accumulated = 0 }
        accumulated += delta

        guard abs(accumulated) >= threshold,
            !(physicalGesture && emittedForPhysicalGesture)
        else {
            return finishIfNeeded(phase)
        }
        emittedForPhysicalGesture = physicalGesture
        emittedForPhaseLessBurst = precise && phase.isEmpty
        accumulated = 0
        let result = accumulatedDirection(delta: delta)
        if phase.contains(.ended) { reset() }
        return result
    }

    public mutating func step(for event: NSEvent) -> Int? {
        step(
            deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
            precise: event.hasPreciseScrollingDeltas, phase: event.phase,
            momentumPhase: event.momentumPhase, timestamp: event.timestamp)
    }

    private mutating func finishIfNeeded(_ phase: NSEvent.Phase) -> Int? {
        if phase.contains(.ended) { reset() }
        return nil
    }

    private func dominantAxis(deltaX: CGFloat, deltaY: CGFloat) -> Axis? {
        guard deltaX != 0 || deltaY != 0 else { return nil }
        return abs(deltaX) >= abs(deltaY) ? .horizontal : .vertical
    }

    private func wheelStep(deltaX: CGFloat, deltaY: CGFloat) -> Int? {
        guard let selectedAxis = dominantAxis(deltaX: deltaX, deltaY: deltaY) else { return nil }
        let delta = selectedAxis == .horizontal ? deltaX : deltaY
        guard abs(delta) >= wheelThreshold else { return nil }
        return delta > 0 ? -1 : 1
    }

    private func accumulatedDirection(delta: CGFloat) -> Int { delta > 0 ? -1 : 1 }
}
