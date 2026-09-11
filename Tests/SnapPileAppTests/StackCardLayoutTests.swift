import AppKit
import ImageIO
import SwiftUI
import XCTest
import UniformTypeIdentifiers
@testable import SnapPile
@testable import SnapPileCore

@MainActor
final class StackCardLayoutTests: XCTestCase {
    func testAllImageFormatsUse175PointSquareCards() {
        let cases = [(1920, 1080), (1024, 1024), (2560, 720)]

        for (width, height) in cases {
            let size = StackLayout.cardSize(pixelWidth: width, pixelHeight: height)
            XCTAssertEqual(size, CGSize(width: 175, height: 175))
        }
    }

    func testTallImagesDoNotEnlargeTheCard() {
        let size = StackLayout.cardSize(pixelWidth: 1080, pixelHeight: 1920)

        XCTAssertEqual(size, CGSize(width: 175, height: 175))
    }

    func testInvalidDimensionsStillProduceAUsableFiniteCard() {
        let size = StackLayout.cardSize(pixelWidth: 0, pixelHeight: 0)

        XCTAssertTrue(size.width.isFinite)
        XCTAssertTrue(size.height.isFinite)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testRenderSyntheticCardsForVisualInspection() throws {
        _ = NSApplication.shared
        let model = AppController()
        defer { model.store.removeAll(includingPinned: true) }
        let outputDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for (name, dimensions) in [("panorama", (1920, 1080)), ("square", (1000, 1000)), ("portrait", (900, 1900))] {
            let (width, height) = dimensions
            let image = try syntheticImage(width: width, height: height)
            let item = ScreenshotItem(pngData: Data(), thumbnail: image,
                                      pixelWidth: width, pixelHeight: height, createdAt: Date())
            let size = StackLayout.cardSize(for: item)
            let hostingView = NSHostingView(rootView: ScreenshotCard(model: model, item: item)
                .environment(\.colorScheme, .light))
            hostingView.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hostingView.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.contentView = hostingView
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: outputDirectory.appendingPathComponent("stack-card-\(name).png"))
            let scale = CGFloat(bitmap.pixelsWide) / size.width
            XCTAssertEqual(scale, CGFloat(bitmap.pixelsHigh) / size.height, accuracy: 0.01)
            XCTAssertEqual(scale, window.backingScaleFactor, accuracy: 0.1)
            let edgeColor = try XCTUnwrap(bitmap.colorAt(x: 4, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(saturation(edgeColor), 0.2,
                                 "Farbige Vorschau fehlt am Rand in \(name)")
        }
    }

    func testNativeStackKeepsBothCardsWithinSmallAndTallViewports() throws {
        _ = NSApplication.shared
        let model = AppController()
        defer { model.store.removeAll(includingPinned: true) }
        let outputDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let cases: [(String, Int, Int, CGFloat?)] = [
            ("small", 295, 236, nil), ("portrait", 180, 380, nil),
            ("square", 240, 240, nil), ("panorama", 480, 135, nil),
            ("476", 180, 380, 476)
        ]
        for (name, width, height, heightLimit) in cases {
            model.store.removeAll(includingPinned: true)
            _ = try model.store.add(pngData: syntheticPNG(width: 64, height: 64), pixelWidth: 64, pixelHeight: 64,
                                    createdAt: Date(timeIntervalSince1970: 1))
            let frontID = try model.store.add(pngData: syntheticPNG(width: width, height: height), pixelWidth: width, pixelHeight: height,
                                             createdAt: Date(timeIntervalSince1970: 2))
            let hostSize = CGSize(width: StackLayout.width,
                                  height: heightLimit ?? StackLayout.height(items: model.store.items, expanded: false))
            let host = NSHostingView(rootView: StackView(model: model).environment(\.colorScheme, .light))
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: hostSize)
            let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -3000, y: -3000), size: hostSize),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.orderOut(nil) }
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()

            let thumbnails = findThumbnailViews(in: host)
            XCTAssertEqual(thumbnails.count, 1, "Der eingeklappte Stapel zeigt eine Front-Thumbnail-View")
            let thumbnail = try XCTUnwrap(thumbnails.first)
            XCTAssertEqual(thumbnail.bounds.size, CGSize(width: 175, height: 175))
            let imageFrame = thumbnail.convert(thumbnail.bounds, to: host)
            XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(imageFrame), "Bild überschreitet Panel in \(name)")
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let y = Int((host.isFlipped ? imageFrame.midY : host.bounds.height - imageFrame.midY) * scale)
            let left = try XCTUnwrap(bitmap.colorAt(x: Int((imageFrame.minX + 3) * scale), y: y)?.usingColorSpace(.deviceRGB))
            let right = try XCTUnwrap(bitmap.colorAt(x: Int((imageFrame.maxX - 3) * scale), y: y)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(saturation(left), 0.2, "Leerer linker Rand in \(name)")
            XCTAssertGreaterThan(saturation(right), 0.2, "Leerer rechter Rand in \(name)")
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: outputDirectory.appendingPathComponent("stack-adaptive-\(name).png"))

            model.store.remove(id: frontID)
            host.setFrameSize(CGSize(width: StackLayout.width, height: StackLayout.height(items: model.store.items, expanded: false)))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
            host.layoutSubtreeIfNeeded()
            let switchedThumbnail = try XCTUnwrap(findThumbnailViews(in: host).first)
            XCTAssertEqual(switchedThumbnail.bounds.width / switchedThumbnail.bounds.height, 1, accuracy: 0.02,
                           "Nach dem Löschen der Frontkarte übernimmt die quadratische Karte im selben Host korrekt")
        }
    }

    private func findThumbnailViews(in view: NSView) -> [DraggableThumbnail.ThumbnailView] {
        var result: [DraggableThumbnail.ThumbnailView] = []
        if let thumbnail = view as? DraggableThumbnail.ThumbnailView { result.append(thumbnail) }
        for child in view.subviews { result.append(contentsOf: findThumbnailViews(in: child)) }
        return result
    }

    private func saturation(_ color: NSColor) -> CGFloat {
        max(color.redComponent, color.greenComponent, color.blueComponent)
            - min(color.redComponent, color.greenComponent, color.blueComponent)
    }

    private func syntheticImage(width: Int, height: Int) throws -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                               bitsPerComponent: 8, bytesPerRow: 0,
                                               space: colorSpace,
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.systemOrange.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: max(1, width / 5), height: height))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: width, height: height))
    }

    private func syntheticPNG(width: Int, height: Int) throws -> Data {
        let image = try syntheticImage(width: width, height: height)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        let rep = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        CGImageDestinationAddImage(destination, rep, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
