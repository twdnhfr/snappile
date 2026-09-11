import CoreGraphics
import XCTest

@testable import SnapPileCore

final class CaptureGeometryTests: XCTestCase {
    func testTopLeftRectOnMainDisplay() {
        let selection = CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            rect: CGRect(x: 100, y: 200, width: 300, height: 150)
        )

        XCTAssertEqual(
            CaptureGeometry.topLeftRect(for: selection),
            CGRect(x: 100, y: 550, width: 300, height: 150))
    }

    func testTopLeftRectOnSecondaryDisplayWithNegativeOrigin() {
        let selection = CaptureSelection(
            displayID: 2,
            screenFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            rect: CGRect(x: -1800, y: 100, width: 400, height: 150)
        )

        XCTAssertEqual(
            CaptureGeometry.topLeftRect(for: selection),
            CGRect(x: 120, y: 830, width: 400, height: 150))
    }

    func testTopLeftRectOnDisplayAboveMainFlipsGlobalY() {
        let selection = CaptureSelection(
            displayID: 3,
            screenFrame: CGRect(x: 0, y: 900, width: 2560, height: 1440),
            rect: CGRect(x: 80, y: 1000, width: 640, height: 360)
        )

        XCTAssertEqual(
            CaptureGeometry.topLeftRect(for: selection),
            CGRect(x: 80, y: 980, width: 640, height: 360))
    }

    func testOutputPixelSizeRoundsRetinaScale() {
        let selection = CaptureSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            rect: CGRect(x: 10, y: 20, width: 101.25, height: 50.75)
        )

        let output = CaptureGeometry.outputPixelSize(for: selection, scale: 2)
        XCTAssertEqual(output.width, 203)
        XCTAssertEqual(output.height, 102)
    }

    func testOutputPixelSizeClampsInvalidNonPositiveRect() {
        let selection = CaptureSelection(
            displayID: 1,
            screenFrame: .zero,
            rect: CGRect(x: 0, y: 0, width: 0, height: 0)
        )

        let output = CaptureGeometry.outputPixelSize(for: selection, scale: 2)
        XCTAssertEqual(output.width, 1)
        XCTAssertEqual(output.height, 1)
    }
}
