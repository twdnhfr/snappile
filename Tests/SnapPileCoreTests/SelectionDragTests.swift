import AppKit
import XCTest

@testable import SnapPileCore

final class SelectionDragTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

    func testResizePreservesAllDragDirections() {
        for point in [
            CGPoint(x: 300, y: 250), CGPoint(x: 100, y: 250),
            CGPoint(x: 300, y: 100), CGPoint(x: 100, y: 100),
        ] {
            var state = SelectionDragState(bounds: bounds)
            state.begin(at: CGPoint(x: 200, y: 180))
            state.update(to: point)
            XCTAssertEqual(
                state.current,
                CGRect(
                    x: min(200, point.x), y: min(180, point.y),
                    width: abs(point.x - 200), height: abs(point.y - 180)))
        }
    }

    func testResizeCanCrossTheAnchorAndUsesMinAbs() {
        var state = SelectionDragState(bounds: bounds)
        state.begin(at: CGPoint(x: 200, y: 180))
        state.update(to: CGPoint(x: 300, y: 250))
        state.update(to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(state.current, CGRect(x: 100, y: 100, width: 100, height: 80))
    }

    func testMovingKeepsSizeAndResumesResizeWithoutJump() {
        var state = SelectionDragState(bounds: bounds)
        state.begin(at: CGPoint(x: 200, y: 180))
        state.update(to: CGPoint(x: 350, y: 300))
        let size = state.current.size
        state.setMoving(true, at: CGPoint(x: 350, y: 300))
        state.update(to: CGPoint(x: 400, y: 320))
        XCTAssertEqual(state.current.size, size)
        let moved = state.current
        state.setMoving(false, at: CGPoint(x: 400, y: 320))
        XCTAssertEqual(state.current, moved)
        state.update(to: CGPoint(x: 450, y: 340))
        XCTAssertEqual(state.current, CGRect(x: moved.minX, y: moved.minY, width: 200, height: 140))
    }

    func testMovingClampsToDisplayAndRepeatedTransitionsAreIdempotent() {
        var state = SelectionDragState(bounds: bounds)
        state.begin(at: CGPoint(x: 100, y: 100))
        state.update(to: CGPoint(x: 300, y: 250))
        state.setMoving(true, at: CGPoint(x: 200, y: 180))
        state.setMoving(true, at: CGPoint(x: 200, y: 180))
        state.update(to: CGPoint(x: 800, y: 600))
        XCTAssertEqual(state.current.maxX, bounds.maxX)
        XCTAssertEqual(state.current.maxY, bounds.maxY)
        let clamped = state.current
        state.setMoving(false, at: CGPoint(x: 800, y: 600))
        state.setMoving(false, at: CGPoint(x: 800, y: 600))
        XCTAssertEqual(state.current, clamped)
        state.update(to: CGPoint(x: 800, y: 600))
        XCTAssertEqual(state.current, clamped)
    }

    func testRawPointerOutsideDisplayDoesNotMoveResizeBaseline() {
        var state = SelectionDragState(bounds: bounds)
        state.begin(at: CGPoint(x: 200, y: 180))
        state.update(to: CGPoint(x: 350, y: 300))
        state.setMoving(true, at: CGPoint(x: 350, y: 300))
        state.update(to: CGPoint(x: 900, y: 700))
        let moved = state.current
        state.setMoving(false, at: CGPoint(x: 900, y: 700))
        state.update(to: CGPoint(x: 900, y: 700))
        XCTAssertEqual(state.current, moved)
    }

    func testResumingAtBottomLeftKeepsSizeAndClampsFinalCorner() {
        var state = SelectionDragState(bounds: bounds)
        state.begin(at: CGPoint(x: 200, y: 180))
        state.update(to: CGPoint(x: 350, y: 300))
        state.setMoving(true, at: CGPoint(x: 350, y: 300))
        state.update(to: .zero)
        XCTAssertEqual(state.current, CGRect(x: 0, y: 0, width: 150, height: 120))
        state.setMoving(false, at: .zero)
        state.update(to: .zero)
        XCTAssertEqual(state.current.size, CGSize(width: 150, height: 120))
        state.update(to: CGPoint(x: 800, y: 600))
        XCTAssertEqual(state.current, bounds)
    }

    func testMovingInEveryDirectionThenResizingKeepsTheActiveCorner() {
        for end in [
            CGPoint(x: 350, y: 300), CGPoint(x: 50, y: 300),
            CGPoint(x: 350, y: 60), CGPoint(x: 50, y: 60),
        ] {
            var state = SelectionDragState(bounds: bounds)
            state.begin(at: CGPoint(x: 200, y: 180))
            state.update(to: end)
            let size = state.current.size
            state.setMoving(true, at: end)
            let movedPointer = CGPoint(x: end.x + 25, y: end.y + 30)
            state.update(to: movedPointer)
            XCTAssertEqual(state.current.size, size)
            state.setMoving(false, at: movedPointer)
            state.update(to: movedPointer)
            XCTAssertEqual(state.current.size, size)
            XCTAssertEqual(state.anchor, CGPoint(x: 225, y: 210))
            XCTAssertEqual(state.endpoint, movedPointer)
        }
    }

    func testSpaceHeldBeforeMouseDownMovesTheZeroSizeOrigin() {
        var state = SelectionDragState(bounds: bounds)
        state.setMoving(true, at: .zero)
        state.begin(at: CGPoint(x: 100, y: 100))
        state.update(to: CGPoint(x: 140, y: 160))
        state.setMoving(false, at: CGPoint(x: 140, y: 160))
        state.update(to: CGPoint(x: 220, y: 200))
        XCTAssertEqual(state.current, CGRect(x: 140, y: 160, width: 80, height: 40))
    }

    @MainActor
    func testOverlayKeyboardAndMouseHandlersReportMovedResizedSelection() throws {
        _ = NSApplication.shared
        var pointer = CGPoint(x: 350, y: 300)
        var results: [CaptureSelection?] = []
        let view = SelectionOverlayView(screenFrame: CGRect(x: -800, y: 40, width: 800, height: 600)) {
            results.append($0)
        }
        view.currentMousePoint = { pointer }
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 200, y: 180)))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: pointer))
        view.keyDown(with: try key(.keyDown, code: 49))
        pointer = .zero
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: pointer))
        // A repeated key event must not reset the movement baseline.
        view.keyDown(with: try key(.keyDown, code: 49, repeating: true))
        view.keyUp(with: try key(.keyUp, code: 49))
        pointer = CGPoint(x: 30, y: 20)
        view.mouseUp(with: try mouse(.leftMouseUp, at: pointer))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(results.first ?? nil).rect,
            CGRect(x: -800, y: 40, width: 180, height: 140))
    }

    @MainActor
    func testMouseUpWhileSpaceHeldCompletesAndEscapeCancels() throws {
        _ = NSApplication.shared
        var pointer = CGPoint(x: 200, y: 180)
        var result: CaptureSelection?
        let view = SelectionOverlayView(screenFrame: bounds) { result = $0 }
        view.currentMousePoint = { pointer }
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: pointer))
        view.keyDown(with: try key(.keyDown, code: 49))
        pointer = CGPoint(x: 240, y: 210)
        view.mouseUp(with: try mouse(.leftMouseUp, at: pointer))
        XCTAssertEqual(try XCTUnwrap(result).rect, CGRect(x: 140, y: 130, width: 100, height: 80))
        view.keyDown(with: try key(.keyDown, code: 53))
        XCTAssertNil(result)
    }

    @MainActor
    private func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @MainActor
    private func key(_ type: NSEvent.EventType, code: UInt16, repeating: Bool = false) throws -> NSEvent {
        // Deliberately unrelated location: keyboard events are not pointer samples.
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type, location: CGPoint(x: 799, y: 599), modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, characters: " ",
                charactersIgnoringModifiers: " ", isARepeat: repeating, keyCode: code))
    }
}
