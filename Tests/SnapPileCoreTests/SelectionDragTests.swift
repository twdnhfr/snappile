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
    func testSpaceReleasedOnAnotherDisplayDoesNotLeaveMoveModeBehind() throws {
        _ = NSApplication.shared
        let keyState = SelectionKeyState()
        var pointer = CGPoint(x: 100, y: 100)
        var results: [CaptureSelection?] = []
        let first = SelectionOverlayView(screenFrame: bounds, keyState: keyState) { results.append($0) }
        let second = SelectionOverlayView(
            screenFrame: bounds.offsetBy(dx: bounds.width, dy: 0), keyState: keyState
        ) { results.append($0) }
        first.currentMousePoint = { pointer }
        second.currentMousePoint = { pointer }

        // Space goes to the first display's key window, the drag and key-up to the second.
        first.keyDown(with: try key(.keyDown, code: 49))
        second.mouseDown(with: try mouse(.leftMouseDown, at: pointer))
        pointer = CGPoint(x: 140, y: 160)
        second.mouseDragged(with: try mouse(.leftMouseDragged, at: pointer))
        second.keyUp(with: try key(.keyUp, code: 49))
        second.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 220, y: 200)))
        XCTAssertEqual(
            try XCTUnwrap(results.last ?? nil).rect, CGRect(x: 940, y: 160, width: 80, height: 40))

        first.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100)))
        first.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 150, y: 160)))
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(try XCTUnwrap(results.last ?? nil).rect, CGRect(x: 100, y: 100, width: 50, height: 60))
    }

    @MainActor
    func testTappingSpaceSwitchesToWindowPickingAndClickPicksTopmostWindow() throws {
        _ = NSApplication.shared
        let keyState = SelectionKeyState()
        keyState.windows = [
            PickableWindow(id: 7, app: "Front", frame: CGRect(x: 100, y: 100, width: 200, height: 150)),
            PickableWindow(id: 8, app: "Back", frame: CGRect(x: 50, y: 50, width: 600, height: 400)),
        ]
        var results: [CaptureSelection?] = []
        let view = SelectionOverlayView(screenFrame: bounds, keyState: keyState) { results.append($0) }
        view.currentMousePoint = { CGPoint(x: 150, y: 150) }

        view.keyDown(with: try key(.keyDown, code: 49, at: 10))
        view.keyUp(with: try key(.keyUp, code: 49, at: 10.1))
        XCTAssertTrue(keyState.picksWindows)
        XCTAssertEqual(keyState.hoveredWindow?.id, 7)

        view.mouseMoved(with: try mouse(.mouseMoved, at: CGPoint(x: 500, y: 300)))
        XCTAssertEqual(keyState.hoveredWindow?.id, 8)
        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 120, y: 120)))
        XCTAssertEqual(results.count, 1)
        let picked = try XCTUnwrap(results.first ?? nil)
        XCTAssertEqual(picked.windowID, 7)
        XCTAssertEqual(picked.rect, CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    @MainActor
    func testTappingSpaceAgainReturnsToAreaSelectionAndHoldingDoesNotSwitch() throws {
        _ = NSApplication.shared
        let keyState = SelectionKeyState()
        var results: [CaptureSelection?] = []
        let view = SelectionOverlayView(screenFrame: bounds, keyState: keyState) { results.append($0) }
        view.currentMousePoint = { .zero }

        // Held longer than a tap: only moves, the mode stays.
        view.keyDown(with: try key(.keyDown, code: 49, at: 10))
        view.keyUp(with: try key(.keyUp, code: 49, at: 11))
        XCTAssertFalse(keyState.picksWindows)

        view.keyDown(with: try key(.keyDown, code: 49, at: 20))
        view.keyUp(with: try key(.keyUp, code: 49, at: 20.1))
        XCTAssertTrue(keyState.picksWindows)
        view.keyDown(with: try key(.keyDown, code: 49, at: 30))
        view.keyUp(with: try key(.keyUp, code: 49, at: 30.1))
        XCTAssertFalse(keyState.picksWindows)

        view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100)))
        view.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 150, y: 160)))
        XCTAssertEqual(try XCTUnwrap(results.first ?? nil).rect, CGRect(x: 100, y: 100, width: 50, height: 60))
        XCTAssertNil(try XCTUnwrap(results.first ?? nil).windowID)
    }

    func testWindowListUsesAppKitCoordinatesAndSkipsOwnAndNonAppWindows() {
        func entry(_ id: Int, pid: Int, layer: Int = 0, bounds: CGRect) -> [String: Any] {
            [
                kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
                kCGWindowOwnerName as String: "App \(id)",
                kCGWindowBounds as String: bounds.dictionaryRepresentation,
            ]
        }
        let windows = PickableWindow.windows(
            from: [
                entry(1, pid: 10, bounds: CGRect(x: 20, y: 30, width: 300, height: 200)),
                entry(2, pid: 99, bounds: CGRect(x: 0, y: 0, width: 300, height: 200)),
                entry(3, pid: 10, layer: 25, bounds: CGRect(x: 0, y: 0, width: 300, height: 200)),
                entry(4, pid: 10, bounds: CGRect(x: 0, y: 0, width: 20, height: 20)),
            ], excludingPID: 99, primaryHeight: 900)
        XCTAssertEqual(
            windows, [PickableWindow(id: 1, app: "App 1", frame: CGRect(x: 20, y: 670, width: 300, height: 200))])
    }

    @MainActor
    func testSelectionEndsWhenAppResignsActiveOrScreensChange() throws {
        _ = NSApplication.shared
        let controller = RegionSelectionController()
        var results: [CaptureSelection?] = []
        controller.begin { results.append($0) }
        // An unchanged display layout keeps the selection open.
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        drainMainQueue()
        XCTAssertTrue(results.isEmpty)

        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        drainMainQueue()
        XCTAssertEqual(results, [nil])

        // Observers are gone once the session ended.
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        drainMainQueue()
        XCTAssertEqual(results, [nil])
    }

    @MainActor
    private func drainMainQueue() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    @MainActor
    private func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @MainActor
    private func key(
        _ type: NSEvent.EventType, code: UInt16, repeating: Bool = false, at timestamp: TimeInterval = 0
    ) throws -> NSEvent {
        // Deliberately unrelated location: keyboard events are not pointer samples.
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type, location: CGPoint(x: 799, y: 599), modifierFlags: [],
                timestamp: timestamp, windowNumber: 0, context: nil, characters: " ",
                charactersIgnoringModifiers: " ", isARepeat: repeating, keyCode: code))
    }
}
