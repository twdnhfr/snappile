import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import SnapPile
@testable import SnapPileCore

@MainActor
final class StackNavigationTests: XCTestCase {
    func testNewCaptureSelectsNewestAndPreservesStoreOrder() throws {
        let model = AppController()
        let first = try addItem(to: model.store, width: 16, height: 10, time: 1)
        let second = try addItem(to: model.store, width: 16, height: 16, time: 2)

        XCTAssertEqual(model.store.items.map(\.id), [second, first])
        XCTAssertEqual(model.selectedScreenshotID, second)
        XCTAssertEqual(model.selectedStackItem?.id, second)
        XCTAssertEqual(model.stackPosition, 1)
    }

    func testBrowseCyclesInBothDirectionsWithoutChangingOrder() throws {
        let model = AppController()
        let oldest = try addItem(to: model.store, width: 16, height: 10, time: 1)
        let middle = try addItem(to: model.store, width: 16, height: 16, time: 2)
        let newest = try addItem(to: model.store, width: 10, height: 16, time: 3)
        let order = model.store.items.map(\.id)

        model.browseStack(by: 1)
        XCTAssertEqual(model.selectedScreenshotID, middle)
        XCTAssertEqual(model.stackPosition, 2)
        model.browseStack(by: 1)
        XCTAssertEqual(model.selectedScreenshotID, oldest)
        XCTAssertEqual(model.stackPosition, 3)
        model.browseStack(by: 1)
        XCTAssertEqual(model.selectedScreenshotID, newest)
        XCTAssertEqual(model.stackPosition, 1)
        model.browseStack(by: -1)
        XCTAssertEqual(model.selectedScreenshotID, oldest)
        XCTAssertEqual(model.stackPosition, 3)
        model.browseStack(by: -1)
        XCTAssertEqual(model.selectedScreenshotID, middle)
        XCTAssertEqual(model.store.items.map(\.id), order)
    }

    func testUnrelatedRemovalAndPinningKeepSelectionAndItemDataStable() throws {
        let model = AppController()
        let old = try addItem(to: model.store, width: 16, height: 10, time: 1)
        let selected = try addItem(to: model.store, width: 16, height: 16, time: 2)
        let newest = try addItem(to: model.store, width: 10, height: 16, time: 3)
        model.browseStack(by: 1)
        let before = try XCTUnwrap(model.store.item(id: selected))

        model.store.togglePin(id: old)
        model.store.remove(id: newest)

        XCTAssertEqual(model.selectedScreenshotID, selected)
        let after = try XCTUnwrap(model.store.item(id: selected))
        XCTAssertEqual(after.createdAt, before.createdAt)
        XCTAssertEqual(after.pngData, before.pngData)
        XCTAssertEqual(after.isPinned, before.isPinned)
        XCTAssertEqual(model.store.items.map(\.id), [selected, old])
    }

    func testRemovingSelectedFallsBackAtSameIndexAndLastItemClamps() throws {
        let model = AppController()
        let old = try addItem(to: model.store, width: 16, height: 10, time: 1)
        let selected = try addItem(to: model.store, width: 16, height: 16, time: 2)
        let newest = try addItem(to: model.store, width: 10, height: 16, time: 3)

        model.browseStack(by: 1)
        model.store.remove(id: selected)
        XCTAssertEqual(model.selectedScreenshotID, old)
        XCTAssertEqual(model.stackPosition, 2)

        model.browseStack(by: -1)
        XCTAssertEqual(model.selectedScreenshotID, newest)
        model.browseStack(by: 1)
        XCTAssertEqual(model.selectedScreenshotID, old)
        model.store.remove(id: old)
        XCTAssertEqual(model.selectedScreenshotID, newest)
        XCTAssertEqual(model.stackPosition, 1)

        model.store.remove(id: newest)
        XCTAssertNil(model.selectedScreenshotID)
        XCTAssertNil(model.selectedStackItem)
        XCTAssertEqual(model.stackPosition, 0)
    }

    func testClearSelectionAndExpansionMakeBrowsingNoOp() throws {
        let model = AppController()
        let first = try addItem(to: model.store, width: 16, height: 10, time: 1)
        _ = try addItem(to: model.store, width: 16, height: 16, time: 2)
        model.isExpanded = true
        let selection = model.selectedScreenshotID

        model.browseStack(by: 1)
        XCTAssertEqual(model.selectedScreenshotID, selection)
        model.store.removeAll(includingPinned: true)
        XCTAssertNil(model.selectedScreenshotID)
        XCTAssertNil(model.selectedStackItem)
        XCTAssertEqual(model.stackPosition, 0)
        XCTAssertFalse(model.store.items.contains(where: { $0.id == first }))
    }

    func testCapacityExpiryAndPinningReconcileSelection() throws {
        let model = AppController()
        model.store.maxItems = 2
        model.store.expiryMinutes = 1
        let now = Date()
        let old = try addItem(to: model.store, width: 16, height: 10, time: now.timeIntervalSince1970 - 120)
        model.store.togglePin(id: old)
        let middle = try addItem(to: model.store, width: 16, height: 16, time: now.timeIntervalSince1970 - 60)
        let newest = try addItem(to: model.store, width: 10, height: 16, time: now.timeIntervalSince1970)
        XCTAssertEqual(model.store.items.map(\.id), [newest, old])
        XCTAssertFalse(model.store.items.contains(where: { $0.id == middle }))
        XCTAssertEqual(model.selectedScreenshotID, newest)

        model.store.expiryMinutes = 1
        model.store.removeExpired()
        XCTAssertEqual(model.selectedScreenshotID, newest)
        XCTAssertTrue(model.store.item(id: old)?.isPinned == true)
        XCTAssertFalse(model.store.items.contains(where: { $0.id == middle }))
    }

    func testExpiringSelectedItemFallsBackToSameIndexAndKeepsPinnedItem() throws {
        let model = AppController()
        model.store.expiryMinutes = 1
        let now = Date().timeIntervalSince1970
        let pinned = try addItem(to: model.store, width: 16, height: 10, time: now - 120)
        model.store.togglePin(id: pinned)
        let selected = try addItem(to: model.store, width: 16, height: 16, time: now - 120)
        let newest = try addItem(to: model.store, width: 10, height: 16, time: now)
        model.browseStack(by: 1)
        XCTAssertEqual(model.selectedScreenshotID, selected)

        model.store.removeExpired()

        XCTAssertEqual(model.store.items.map(\.id), [newest, pinned])
        XCTAssertEqual(model.selectedScreenshotID, pinned)
        XCTAssertEqual(model.selectedStackItem?.id, pinned)
        XCTAssertTrue(model.store.item(id: pinned)?.isPinned == true)
    }

    @discardableResult
    private func addItem(to store: ScreenshotStore, width: Int, height: Int, time: TimeInterval) throws -> UUID {
        try store.add(
            pngData: syntheticPNG(width: width, height: height), pixelWidth: width,
            pixelHeight: height, createdAt: Date(timeIntervalSince1970: time))
    }

    private func syntheticPNG(width: Int, height: Int) throws -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4, bitsPerPixel: 32)!
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                rep.bitmapData![offset] = UInt8((x * 255) / max(width - 1, 1))
                rep.bitmapData![offset + 1] = UInt8((y * 255) / max(height - 1, 1))
                rep.bitmapData![offset + 2] = 96
                rep.bitmapData![offset + 3] = 255
            }
        }
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
