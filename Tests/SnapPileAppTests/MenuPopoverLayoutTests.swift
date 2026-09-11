import AppKit
import SwiftUI
import XCTest

@testable import SnapPile
@testable import SnapPileCore

@MainActor
final class MenuPopoverLayoutTests: XCTestCase {
    func testHostingViewKeepsProposedFrameAcrossItemCountTransitions() throws {
        _ = NSApplication.shared
        let model = AppController()
        defer { model.store.removeAll(includingPinned: true) }
        let controller = NSHostingController(
            rootView: FixedMenuPopoverView(
                model: model, size: MenuPopoverLayout.size(itemCount: 0)))
        controller.sizingOptions = []

        for itemCount in 0...4 {
            model.store.removeAll(includingPinned: true)
            for index in 0..<itemCount {
                try addSyntheticItem(to: model.store, color: index.isMultiple(of: 2) ? .systemBlue : .systemGreen)
            }
            let expected = MenuPopoverLayout.size(itemCount: itemCount)

            // Exercise the same kind of stale proposals that caused the original
            // popover bug, then apply the explicit size used by the wrapper.
            for proposedHeight in [CGFloat(1), expected.height + 120, CGFloat(900)] {
                let result = measure(
                    controller: controller, model: model, size: expected,
                    proposedHeight: proposedHeight)
                XCTAssertEqual(
                    result.hostFrame.size, expected,
                    "Host-Größe driftet bei \(itemCount) Elementen und Proposal \(proposedHeight)")
                XCTAssertEqual(result.fittingSize.width, expected.width, accuracy: 1)
                XCTAssertEqual(
                    result.fittingSize.height, expected.height, accuracy: 1,
                    "Fitting-Size driftet bei \(itemCount) Elementen")
            }
        }
    }

    func testEmptyMenuRendersHeaderNearTopEvenAfterOversizedProposal() throws {
        _ = NSApplication.shared
        let model = AppController()
        let size = MenuPopoverLayout.size(itemCount: 0)
        let content = FixedMenuPopoverView(model: model, size: size)
            .environment(\.colorScheme, .dark)
            .background(Color(red: 0.13, green: 0.13, blue: 0.14))
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 320, height: 900)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.height, Int(size.height * 2))
        let bitmap = NSBitmapImageRep(cgImage: image)
        var firstAccentRow: Int?
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.greenComponent > 0.35 && color.greenComponent > color.redComponent * 1.6
                    && color.greenComponent > color.blueComponent * 1.08
                {
                    firstAccentRow = y
                    break
                }
            }
            if firstAccentRow != nil { break }
        }
        XCTAssertLessThan(try XCTUnwrap(firstAccentRow), 100, "Menükopf ist nach unten verschoben")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: TestOutput.directory().appendingPathComponent("popover-empty.png"))
    }

    private struct Measurement {
        let hostFrame: NSRect
        let fittingSize: NSSize
    }

    private func measure(
        controller: NSHostingController<FixedMenuPopoverView>, model: AppController,
        size: NSSize, proposedHeight: CGFloat
    ) -> Measurement {
        controller.rootView = FixedMenuPopoverView(model: model, size: size)
        controller.preferredContentSize = size
        let host = controller.view
        host.frame = NSRect(x: 0, y: 0, width: 320, height: proposedHeight)
        let window = NSWindow(
            contentRect: host.frame, styleMask: .borderless,
            backing: .buffered, defer: false)
        window.contentView = host
        window.setContentSize(size)
        host.setFrameSize(size)
        window.contentView?.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()

        return Measurement(
            hostFrame: host.frame,
            fittingSize: host.fittingSize)
    }

    private func addSyntheticItem(to store: ScreenshotStore, color: NSColor) throws {
        let width = 16
        let height = 10
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
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        _ = try store.add(pngData: data, pixelWidth: width, pixelHeight: height)
    }
}
