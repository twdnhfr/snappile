import AppKit
import XCTest

@testable import SnapPileCore

final class StackScrollGestureTests: XCTestCase {
    private let none: NSEvent.Phase = []

    func testOrthogonalJitterDoesNotEraseNegativeAccumulation() {
        var gesture = StackScrollGesture()
        XCTAssertNil(
            gesture.step(deltaX: -15, deltaY: 0, precise: true, phase: .began, momentumPhase: none, timestamp: 1))
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 2, precise: true, phase: .changed, momentumPhase: none, timestamp: 1.01))
        XCTAssertEqual(
            gesture.step(deltaX: -11, deltaY: 0, precise: true, phase: .changed, momentumPhase: none, timestamp: 1.02),
            1)
    }

    func testPreciseVerticalGestureAndMomentumTail() {
        var gesture = StackScrollGesture()
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 8, precise: true, phase: .began, momentumPhase: none, timestamp: 1))
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 10, precise: true, phase: .changed, momentumPhase: none, timestamp: 1.01))
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: 10, precise: true, phase: .changed, momentumPhase: none, timestamp: 1.02),
            -1)
        XCTAssertNil(
            gesture.step(
                deltaX: 0, deltaY: 100, precise: true, phase: .changed, momentumPhase: .changed, timestamp: 1.03))
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 100, precise: true, phase: .ended, momentumPhase: .ended, timestamp: 1.04))
    }

    func testDiagonalLocksDominantAxisAndReversalStartsFreshGesture() {
        var gesture = StackScrollGesture()
        XCTAssertNil(
            gesture.step(deltaX: 20, deltaY: 5, precise: true, phase: .began, momentumPhase: none, timestamp: 2))
        XCTAssertEqual(
            gesture.step(deltaX: 8, deltaY: 30, precise: true, phase: .changed, momentumPhase: none, timestamp: 2.01),
            -1)
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: -40, precise: true, phase: .changed, momentumPhase: none, timestamp: 2.02))
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: -1, precise: true, phase: .ended, momentumPhase: none, timestamp: 2.03))
    }

    func testMouseNotchesRemainIndependentAndDoNotRequireCooldown() {
        var gesture = StackScrollGesture()
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: 1, precise: false, phase: none, momentumPhase: none, timestamp: 3), -1)
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: -1, precise: false, phase: none, momentumPhase: none, timestamp: 3.001), 1)
    }

    func testPrecisePhaselessAccumulationSettlesAfterGap() {
        var gesture = StackScrollGesture()
        XCTAssertNil(gesture.step(deltaX: 0, deltaY: 12, precise: true, phase: none, momentumPhase: none, timestamp: 4))
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: 14, precise: true, phase: none, momentumPhase: none, timestamp: 4.01), -1)
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 20, precise: true, phase: none, momentumPhase: none, timestamp: 4.20))
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: 6, precise: true, phase: none, momentumPhase: none, timestamp: 4.21), -1)
    }

    func testCancelledGestureNeverEmitsAndInvalidInputIsIgnored() {
        var gesture = StackScrollGesture()
        XCTAssertNil(
            gesture.step(deltaX: 20, deltaY: 0, precise: true, phase: .began, momentumPhase: none, timestamp: 5))
        XCTAssertNil(
            gesture.step(deltaX: 20, deltaY: 0, precise: true, phase: .cancelled, momentumPhase: none, timestamp: 5.01))
        XCTAssertNil(
            gesture.step(deltaX: .nan, deltaY: 40, precise: true, phase: .changed, momentumPhase: none, timestamp: 5.02)
        )
    }

    func testZeroBeganThenChangedEmitsOnlyOnceAndZeroEndedResets() {
        var gesture = StackScrollGesture()
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 0, precise: true, phase: .began, momentumPhase: none, timestamp: 6))
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: 50, precise: true, phase: .changed, momentumPhase: none, timestamp: 6.01),
            -1)
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 50, precise: true, phase: .changed, momentumPhase: none, timestamp: 6.02))
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 0, precise: true, phase: .ended, momentumPhase: none, timestamp: 6.03))
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: -50, precise: true, phase: .began, momentumPhase: none, timestamp: 6.1), 1)
    }

    func testZeroCancelResetsGesture() {
        var gesture = StackScrollGesture()
        XCTAssertNil(
            gesture.step(deltaX: 10, deltaY: 0, precise: true, phase: .began, momentumPhase: none, timestamp: 7))
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 0, precise: true, phase: .cancelled, momentumPhase: none, timestamp: 7.01))
        XCTAssertEqual(
            gesture.step(deltaX: -50, deltaY: 0, precise: true, phase: .changed, momentumPhase: none, timestamp: 7.02),
            1)
    }

    func testPhaselessBurstCannotRunAway() {
        var gesture = StackScrollGesture()
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: 30, precise: true, phase: none, momentumPhase: none, timestamp: 8), -1)
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 100, precise: true, phase: none, momentumPhase: none, timestamp: 8.05))
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 100, precise: true, phase: none, momentumPhase: none, timestamp: 8.11))
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: 30, precise: true, phase: none, momentumPhase: none, timestamp: 8.25), -1)
    }

    func testSmallOrthogonalNoiseDoesNotLockAxis() {
        var gesture = StackScrollGesture()
        XCTAssertNil(
            gesture.step(deltaX: 0.1, deltaY: 0, precise: true, phase: .began, momentumPhase: none, timestamp: 9))
        XCTAssertNil(
            gesture.step(deltaX: 0, deltaY: 2.8, precise: true, phase: .changed, momentumPhase: none, timestamp: 9.01))
        XCTAssertEqual(
            gesture.step(deltaX: 0, deltaY: 25, precise: true, phase: .changed, momentumPhase: none, timestamp: 9.02),
            -1)
    }
}
