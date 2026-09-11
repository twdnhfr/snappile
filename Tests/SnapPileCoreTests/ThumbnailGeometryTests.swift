import AppKit
import XCTest
@testable import SnapPileCore

final class ThumbnailGeometryTests: XCTestCase {
    private let square = NSRect(x: 0, y: 0, width: 175, height: 175)

    func testPortraitFillCoversSquareAndIsCentered() {
        let rect = DraggableThumbnail.ThumbnailView.drawRect(imageSize: NSSize(width: 100, height: 200), in: square, contentMode: .fill)
        XCTAssertEqual(rect, NSRect(x: -0.0, y: -87.5, width: 175, height: 350))
        XCTAssertEqual(rect.midX, square.midX)
        XCTAssertEqual(rect.midY, square.midY)
    }

    func testLandscapeFillCoversSquareAndIsCentered() {
        let rect = DraggableThumbnail.ThumbnailView.drawRect(imageSize: NSSize(width: 200, height: 100), in: square, contentMode: .fill)
        XCTAssertEqual(rect, NSRect(x: -87.5, y: 0, width: 350, height: 175))
        XCTAssertEqual(rect.midX, square.midX)
        XCTAssertEqual(rect.midY, square.midY)
    }

    func testFitContainsPortraitAndLandscape() {
        let portrait = DraggableThumbnail.ThumbnailView.drawRect(imageSize: NSSize(width: 100, height: 200), in: square, contentMode: .fit)
        XCTAssertEqual(portrait, NSRect(x: 43.75, y: 0, width: 87.5, height: 175))
        let landscape = DraggableThumbnail.ThumbnailView.drawRect(imageSize: NSSize(width: 200, height: 100), in: square, contentMode: .fit)
        XCTAssertEqual(landscape, NSRect(x: 0, y: 43.75, width: 175, height: 87.5))
    }
}
