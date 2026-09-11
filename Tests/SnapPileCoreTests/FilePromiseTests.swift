import AppKit
import XCTest
@testable import SnapPileCore

final class FilePromiseTests: XCTestCase {
    private func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 10, height: 10).fill(); image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return representation.representation(using: .png, properties: [:])!
    }

    func testProviderExportsExactlyOnePNGRepresentationOnUniquePasteboard() throws {
        let data = pngData()
        let provider = PNGFilePromiseProvider(data: data, filename: "Screenshot.png")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(pasteboard.writeObjects([provider]))
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.data(forType: .png), data)
    }

    func testPromiseDelegateWritesPNGToRequestedURL() throws {
        let data = pngData()
        let delegate = PNGFilePromiseDelegate(data: data, filename: "Screenshot.png")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapPileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Screenshot.png")
        let expectation = expectation(description: "file promise completion")
        var completionError: Error?

        delegate.filePromiseProvider(NSFilePromiseProvider(fileType: "public.png", delegate: delegate),
                                     writePromiseTo: destination) { error in
            completionError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertNil(completionError)
        XCTAssertEqual(try Data(contentsOf: destination), data)
    }
}
