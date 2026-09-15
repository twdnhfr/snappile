import Carbon
import XCTest

@testable import SnapPileCore

final class HotKeyControllerTests: XCTestCase {
    func testChordTriggersOnlyOnUnblockedRisingBothOptions() {
        var state = OptionChordState()
        XCTAssertFalse(state.update(leftDown: false, rightDown: false, blocked: false))
        XCTAssertFalse(state.update(leftDown: true, rightDown: false, blocked: false))
        XCTAssertTrue(state.update(leftDown: true, rightDown: true, blocked: false))
        XCTAssertFalse(state.update(leftDown: true, rightDown: true, blocked: false))
        XCTAssertFalse(state.update(leftDown: false, rightDown: true, blocked: false))
        XCTAssertTrue(state.update(leftDown: true, rightDown: true, blocked: false))
    }

    func testBlockedChordDoesNotTriggerWhenBlockIsReleasedWhileHeld() {
        var state = OptionChordState()
        XCTAssertFalse(state.update(leftDown: true, rightDown: true, blocked: true))
        XCTAssertFalse(state.update(leftDown: true, rightDown: true, blocked: false))
        XCTAssertFalse(state.update(leftDown: false, rightDown: false, blocked: false))
        XCTAssertTrue(state.update(leftDown: true, rightDown: true, blocked: false))
    }

    func testDeviceSpecificOptionFlagsTrackLeftAndRightIndependently() {
        let left = OptionModifierSnapshot(rawFlags: 0x80020)
        XCTAssertTrue(left.leftDown)
        XCTAssertFalse(left.rightDown)
        let both = OptionModifierSnapshot(rawFlags: 0x80060)
        XCTAssertTrue(both.leftDown)
        XCTAssertTrue(both.rightDown)
        let right = OptionModifierSnapshot(rawFlags: 0x80040)
        XCTAssertFalse(right.leftDown)
        XCTAssertTrue(right.rightDown)
        let released = OptionModifierSnapshot(rawFlags: 0x60)
        XCTAssertFalse(released.leftDown)
        XCTAssertFalse(released.rightDown)
    }

    func testRawModifierEventSequenceTriggersAndRearmsWithoutGlobalKeyPolling() {
        var chord = OptionChordState()
        func feed(_ raw: UInt64) -> Bool {
            let event = OptionModifierSnapshot(rawFlags: raw)
            return chord.update(leftDown: event.leftDown, rightDown: event.rightDown, blocked: event.blocked)
        }
        XCTAssertFalse(feed(0x80020))
        XCTAssertTrue(feed(0x80060))
        XCTAssertFalse(feed(0x80060))
        XCTAssertFalse(feed(0x80040))
        XCTAssertTrue(feed(0x80060))
        XCTAssertFalse(feed(0))
        XCTAssertFalse(feed(0x180060))  // Command + both Option
        XCTAssertFalse(feed(0x80060))  // Command release does not trigger
        XCTAssertFalse(feed(0x80020))
        XCTAssertTrue(feed(0x80060))
    }

    @MainActor
    func testEnabledSystemShortcutsConflictIgnoringFunctionFlag() {
        let shortcuts: [[String: Any]] = [
            // ⌘⇧4, enabled
            [kHISymbolicHotKeyCode: 21, kHISymbolicHotKeyModifiers: cmdKey | shiftKey, kHISymbolicHotKeyEnabled: true],
            // ⌃F1 with the function-key flag macOS adds, enabled
            [
                kHISymbolicHotKeyCode: 122, kHISymbolicHotKeyModifiers: 0x20000 | controlKey,
                kHISymbolicHotKeyEnabled: 1,
            ],
            // ⌃⌥S, disabled
            [
                kHISymbolicHotKeyCode: 1, kHISymbolicHotKeyModifiers: controlKey | optionKey,
                kHISymbolicHotKeyEnabled: 0,
            ],
        ]
        func conflicts(_ code: UInt32, _ modifiers: Int) -> Bool {
            HotKeyController.isSystemShortcut(keyCode: code, modifiers: UInt32(modifiers), in: shortcuts)
        }
        XCTAssertTrue(conflicts(21, cmdKey | shiftKey))
        XCTAssertFalse(conflicts(21, cmdKey))
        XCTAssertTrue(conflicts(122, controlKey))
        XCTAssertFalse(conflicts(1, controlKey | optionKey))
    }
}
