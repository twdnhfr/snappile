import AppKit
import XCTest

@testable import SnapPileCore

@MainActor
final class ScreenshotStoreTests: XCTestCase {
    private func png(_ color: NSColor = .red, width: Int = 10, height: Int = 10) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4, bitsPerPixel: 32)!
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.usingColorSpace(.deviceRGB)!.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            rep.bitmapData![index] = UInt8(red * 255)
            rep.bitmapData![index + 1] = UInt8(green * 255)
            rep.bitmapData![index + 2] = UInt8(blue * 255)
            rep.bitmapData![index + 3] = UInt8(alpha * 255)
        }
        return rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
    }

    func testAddsAndTracksBytes() throws {
        let data = png()
        let store = ScreenshotStore()
        let id = try store.add(pngData: data, pixelWidth: 10, pixelHeight: 10)
        XCTAssertEqual(store.item(id: id)?.pngData, data)
        XCTAssertEqual(store.totalBytes, data.count)
        XCTAssertEqual(store.items.first?.thumbnail.size.width, 10)
    }

    func testExpiresOnlyUnpinnedAndUnpinThenExpires() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let store = ScreenshotStore(expiryMinutes: 1, now: { clock })
        let old = try store.add(pngData: png(), pixelWidth: 10, pixelHeight: 10, createdAt: clock)
        let pinned = try store.add(pngData: png(.blue), pixelWidth: 10, pixelHeight: 10, createdAt: clock)
        store.togglePin(id: pinned)
        clock.addTimeInterval(61)
        store.removeExpired()
        XCTAssertNil(store.item(id: old))
        XCTAssertNotNil(store.item(id: pinned))
        store.togglePin(id: pinned)
        store.removeExpired()
        XCTAssertNil(store.item(id: pinned))
    }

    func testRemovalsWithoutEffectDoNotPublish() throws {
        var clock = Date(timeIntervalSince1970: 1000)
        let store = ScreenshotStore(expiryMinutes: 1, now: { clock })
        let id = try store.add(pngData: png(), pixelWidth: 10, pixelHeight: 10, createdAt: clock)
        var publishes = 0
        let subscription = store.$items.dropFirst().sink { _ in publishes += 1 }
        defer { subscription.cancel() }

        store.removeExpired()
        store.remove(id: UUID())
        store.enforceLimits()
        XCTAssertEqual(publishes, 0)

        clock.addTimeInterval(61)
        store.removeExpired()
        XCTAssertEqual(publishes, 1)
        XCTAssertNil(store.item(id: id))
    }

    func testExpiresAtExactDeadline() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var clock = start
        let store = ScreenshotStore(expiryMinutes: 1, now: { clock })
        let id = try store.add(pngData: png(), pixelWidth: 10, pixelHeight: 10, createdAt: start)

        clock = start.addingTimeInterval(60)
        store.removeExpired()

        XCTAssertNil(
            store.item(id: id), "Ein unangehefteter Screenshot soll am exakten Ablaufzeitpunkt entfernt werden")
    }

    func testEvictsOldestUnpinned() throws {
        let store = ScreenshotStore(maxItems: 2)
        let first = try store.add(
            pngData: png(), pixelWidth: 10, pixelHeight: 10, createdAt: Date(timeIntervalSince1970: 1))
        let second = try store.add(
            pngData: png(.blue), pixelWidth: 10, pixelHeight: 10, createdAt: Date(timeIntervalSince1970: 2))
        let third = try store.add(
            pngData: png(.green), pixelWidth: 10, pixelHeight: 10, createdAt: Date(timeIntervalSince1970: 3))
        XCTAssertNil(store.item(id: first))
        XCTAssertNotNil(store.item(id: second))
        XCTAssertNotNil(store.item(id: third))
    }

    func testPinnedCapacityFailureIsAtomic() throws {
        let store = ScreenshotStore(maxItems: 2)
        let first = try store.add(pngData: png(), pixelWidth: 10, pixelHeight: 10)
        store.togglePin(id: first)
        let second = try store.add(pngData: png(.blue), pixelWidth: 10, pixelHeight: 10)
        store.togglePin(id: second)
        let before = store.items.map(\.id)
        XCTAssertThrowsError(try store.add(pngData: png(.green), pixelWidth: 10, pixelHeight: 10))
        XCTAssertEqual(store.items.map(\.id), before)
    }

    func testPinnedByteCapacityFailureIsAtomic() throws {
        let firstData = png()
        let secondData = png(.blue)
        let store = ScreenshotStore(maxItems: 10, byteLimit: firstData.count + secondData.count - 1)
        let first = try store.add(pngData: firstData, pixelWidth: 10, pixelHeight: 10)
        store.togglePin(id: first)
        let before = store.items.map(\.id)
        let beforeBytes = store.totalBytes

        XCTAssertThrowsError(try store.add(pngData: secondData, pixelWidth: 10, pixelHeight: 10)) { error in
            XCTAssertEqual(error as? ScreenshotStoreError, .capacityExceeded)
        }
        XCTAssertEqual(store.items.map(\.id), before)
        XCTAssertEqual(store.totalBytes, beforeBytes)
    }

    func testItemsAreNewestFirstForDeterministicDistinctDates() throws {
        let store = ScreenshotStore(maxItems: 10)
        let oldest = try store.add(
            pngData: png(), pixelWidth: 10, pixelHeight: 10,
            createdAt: Date(timeIntervalSince1970: 1))
        let newest = try store.add(
            pngData: png(.blue), pixelWidth: 10, pixelHeight: 10,
            createdAt: Date(timeIntervalSince1970: 3))
        let middle = try store.add(
            pngData: png(.green), pixelWidth: 10, pixelHeight: 10,
            createdAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(store.items.map(\.id), [newest, middle, oldest])
    }

    func testItemsKeepInsertionOrderWhenCreatedAtIsEqual() throws {
        let date = Date(timeIntervalSince1970: 1)
        let store = ScreenshotStore(maxItems: 10)
        let first = try store.add(pngData: png(), pixelWidth: 10, pixelHeight: 10, createdAt: date)
        let second = try store.add(pngData: png(.blue), pixelWidth: 10, pixelHeight: 10, createdAt: date)

        XCTAssertEqual(store.items.map(\.id), [second, first])
    }

    func testReducingMaxItemsEvictsOldestUnpinnedImmediately() throws {
        let store = ScreenshotStore(maxItems: 3)
        let oldest = try store.add(
            pngData: png(), pixelWidth: 10, pixelHeight: 10,
            createdAt: Date(timeIntervalSince1970: 1))
        let middle = try store.add(
            pngData: png(.blue), pixelWidth: 10, pixelHeight: 10,
            createdAt: Date(timeIntervalSince1970: 2))
        let newest = try store.add(
            pngData: png(.green), pixelWidth: 10, pixelHeight: 10,
            createdAt: Date(timeIntervalSince1970: 3))

        store.maxItems = 2

        XCTAssertNil(store.item(id: oldest))
        XCTAssertEqual(store.items.map(\.id), [newest, middle])
    }

    func testReducingMaxItemsKeepsPinnedItemsUntilUnpinned() throws {
        let store = ScreenshotStore(maxItems: 2)
        let oldest = try store.add(
            pngData: png(), pixelWidth: 10, pixelHeight: 10,
            createdAt: Date(timeIntervalSince1970: 1))
        let middle = try store.add(
            pngData: png(.blue), pixelWidth: 10, pixelHeight: 10,
            createdAt: Date(timeIntervalSince1970: 2))
        store.togglePin(id: oldest)
        store.togglePin(id: middle)

        store.maxItems = 1
        XCTAssertEqual(store.items.count, 2, "Pinned items may temporarily exceed the new limit")
        XCTAssertNotNil(store.item(id: oldest))
        XCTAssertNotNil(store.item(id: middle))

        store.togglePin(id: oldest)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.item(id: oldest))
        XCTAssertNotNil(store.item(id: middle))
    }

    func testRejectsInvalidPNGAndMismatchedDimensions() {
        let store = ScreenshotStore()
        XCTAssertThrowsError(try store.add(pngData: Data("no".utf8), pixelWidth: 1, pixelHeight: 1)) { error in
            XCTAssertEqual(error as? ScreenshotStoreError, .invalidPNG)
        }
        XCTAssertThrowsError(try store.add(pngData: png(), pixelWidth: 11, pixelHeight: 10)) { error in
            XCTAssertEqual(error as? ScreenshotStoreError, .invalidDimensions)
        }
        XCTAssertThrowsError(try store.add(pngData: png(), pixelWidth: 0, pixelHeight: 10)) { error in
            XCTAssertEqual(error as? ScreenshotStoreError, .invalidDimensions)
        }
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.totalBytes, 0)
    }
}
