import AppKit
import ImageIO
import SnapPileCore
import UniformTypeIdentifiers

extension AppController {
    func insertDemoImages() {
        for variant in 0..<4 {
            guard let image = makeDemoImage(variant: variant) else { continue }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
            else { continue }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { continue }
            _ = try? store.add(pngData: data as Data, pixelWidth: image.width, pixelHeight: image.height)
        }
    }
}

private func makeDemoImage(variant: Int) -> CGImage? {
    let width = 1280
    let height = 800
    guard
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.15, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.20, alpha: 1).setFill()
    NSRect(x: 0, y: 738, width: width, height: 62).fill()
    for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 28 + index * 28, y: 760, width: 13, height: 13)).fill()
    }
    drawText(L10n.text("EXAMPLE  /  SNAPPILE"), x: 505, y: 758, size: 15, color: .secondaryLabelColor)
    let titles = [
        L10n.text("Capture an idea."), L10n.text("Context for your agent."), L10n.text("Small details. Big impact."),
        L10n.text("Ready for the next prompt."),
    ]
    drawText(titles[variant], x: 74, y: 630, size: 42, color: .white, weight: .semibold)
    drawText(
        L10n.text("SCREENSHOT → PILE → AI CHAT"), x: 77, y: 588, size: 17,
        color: NSColor(calibratedRed: 0.28, green: 0.83, blue: 0.69, alpha: 1))
    for i in 0..<3 {
        let rect = NSRect(x: 76 + i * 382, y: 190, width: 354, height: 300)
        NSColor(calibratedRed: 0.15 + Double(i) * 0.02, green: 0.20, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
        drawText(
            ["01", "02", "03"][i], x: CGFloat(rect.minX + 25), y: 426, size: 17,
            color: NSColor(calibratedRed: 0.28, green: 0.83, blue: 0.69, alpha: 1))
        drawText(
            [L10n.text("Capture"), L10n.text("Collect"), L10n.text("Share")][i], x: rect.minX + 25, y: 369, size: 25,
            color: .white,
            weight: .semibold)
        for j in 0..<3 {
            NSColor(white: 0.7, alpha: 0.14).setFill()
            let bar = NSRect(x: rect.minX + 25, y: CGFloat(304 - j * 26), width: CGFloat(270 - j * 35), height: 9)
            NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
        }
    }
    drawText(
        L10n.text("Synthetic demo · no real screen data"), x: 77, y: 75, size: 16,
        color: NSColor(white: 0.65, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()
}
private func drawText(
    _ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular
) {
    (text as NSString).draw(
        at: NSPoint(x: x, y: y),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
