import AppKit
import Darwin
import XCTest
@testable import SnapPileCore

@MainActor
final class DragTransferTests: XCTestCase {
    private func item(id: UUID = UUID(), createdAt: Date = Date(timeIntervalSince1970: 0)) -> ScreenshotItem {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 40, bitsPerPixel: 32)!
        for offset in stride(from: 0, to: 400, by: 4) {
            bitmap.bitmapData![offset] = 220
            bitmap.bitmapData![offset + 1] = 50
            bitmap.bitmapData![offset + 2] = 80
            bitmap.bitmapData![offset + 3] = 255
        }
        let data = bitmap.representation(using: .png, properties: [:])!
        return ScreenshotItem(id: id, pngData: data, thumbnail: NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: 10, height: 10)),
                              pixelWidth: 10, pixelHeight: 10, createdAt: createdAt)
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SnapPileDragTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testOneDragItemContainsExistingFileAndOriginalPNG() throws {
        let base = directory()
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = TemporaryScreenshotFiles(baseDirectory: base)
        let source = item()
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path), "No disk write before drag")
        let file = try cache.beginDrag(for: source)
        XCTAssertEqual(try Data(contentsOf: file.url), source.pngData)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([ScreenshotDragPasteboard.item(pngData: source.pngData, fileURL: file.url)]))
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.data(forType: .png), source.pngData)
        XCTAssertEqual(pasteboard.string(forType: .fileURL), file.url.absoluteString)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls, [file.url])
    }

    func testFilesAndDirectoriesArePrivate() throws {
        let base = directory()
        defer { try? FileManager.default.removeItem(at: base) }
        let file = try TemporaryScreenshotFiles(baseDirectory: base).beginDrag(for: item())
        for (url, permission) in [(file.url, 0o600), (file.url.deletingLastPathComponent(), 0o700), (base, 0o700)] {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, permission)
        }
    }

    func testFileSurvivesEndOfDragAndExpiresAfterGracePeriod() throws {
        let base = directory()
        defer { try? FileManager.default.removeItem(at: base) }
        var date = Date(timeIntervalSince1970: 1_000)
        let cache = TemporaryScreenshotFiles(baseDirectory: base, retention: 30, now: { date })
        let file = try cache.beginDrag(for: item())
        date.addTimeInterval(100)
        cache.removeExpired()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path), "Active drag must not expire")
        cache.finishDrag(file)
        cache.removeExpired()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path), "Recipient may read asynchronously")
        date.addTimeInterval(29)
        cache.removeExpired()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        date.addTimeInterval(1)
        cache.removeExpired()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testRepeatedAndConcurrentDragsReuseFileAndRenewLease() throws {
        let base = directory()
        defer { try? FileManager.default.removeItem(at: base) }
        var date = Date(timeIntervalSince1970: 1_000)
        let cache = TemporaryScreenshotFiles(baseDirectory: base, retention: 30, now: { date })
        let source = item()
        let first = try cache.beginDrag(for: source)
        let second = try cache.beginDrag(for: source)
        XCTAssertEqual(first.url, second.url)
        cache.finishDrag(first)
        cache.finishDrag(first) // Duplicate completion must not release the second drag.
        date.addTimeInterval(100)
        cache.removeExpired()
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        cache.finishDrag(second)
        date.addTimeInterval(20)
        let third = try cache.beginDrag(for: source)
        cache.finishDrag(third)
        date.addTimeInterval(20)
        cache.removeExpired()
        XCTAssertTrue(FileManager.default.fileExists(atPath: third.url.path))
    }

    func testSameTimestampHasDistinctURLsAndCleanupIsScoped() throws {
        let base = directory()
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = TemporaryScreenshotFiles(baseDirectory: base)
        let first = try cache.beginDrag(for: item())
        let second = try cache.beginDrag(for: item())
        XCTAssertNotEqual(first.url, second.url)
        let unrelated = base.appendingPathComponent("keep.txt")
        try Data("not an export".utf8).write(to: unrelated)
        cache.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testExportRemainsReadableAfterScreenshotIsDeletedFromStore() throws {
        let base = directory()
        defer { try? FileManager.default.removeItem(at: base) }
        let cache = TemporaryScreenshotFiles(baseDirectory: base)
        let store = ScreenshotStore()
        let source = item()
        let id = try store.add(pngData: source.pngData, pixelWidth: 10, pixelHeight: 10)
        let file = try cache.beginDrag(for: XCTUnwrap(store.item(id: id)))
        cache.finishDrag(file)
        store.remove(id: id)
        XCTAssertEqual(try Data(contentsOf: file.url), source.pngData)
    }

    func testCapacityDoesNotEvictAnUnexpiredExport() throws {
        let base = directory()
        defer { try? FileManager.default.removeItem(at: base) }
        var date = Date(timeIntervalSince1970: 1_000)
        let source = item()
        let cache = TemporaryScreenshotFiles(baseDirectory: base, retention: 30, byteLimit: source.pngData.count,
                                              now: { date })
        let first = try cache.beginDrag(for: source)
        cache.finishDrag(first)
        XCTAssertThrowsError(try cache.beginDrag(for: item()))
        XCTAssertEqual(try Data(contentsOf: first.url), source.pngData)
        date.addTimeInterval(30)
        _ = try cache.beginDrag(for: item())
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
    }

    func testCleanupRemovesOnlyDeadSessionDirectories() throws {
        let base = directory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        let deadPID = Int32.max
        XCTAssertEqual(kill(deadPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        let stale = base.appendingPathComponent("\(deadPID)-\(UUID().uuidString)")
        let running = base.appendingPathComponent("\(getpid())-\(UUID().uuidString)")
        let unrelated = base.appendingPathComponent("keep")
        for dir in [stale, running, unrelated] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false) }
        TemporaryScreenshotFiles(baseDirectory: base).removeExpired()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: running.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testSymlinkBaseIsRejectedWithoutWritingIntoDestination() throws {
        let base = directory()
        let destination = directory()
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: base, withDestinationURL: destination)
        defer {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: destination)
        }
        XCTAssertThrowsError(try TemporaryScreenshotFiles(baseDirectory: base).beginDrag(for: item()))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }
}
