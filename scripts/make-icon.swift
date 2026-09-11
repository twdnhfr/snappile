import AppKit
import Foundation

enum IconError: Error, CustomStringConvertible {
    case usage
    case missingSource(URL)
    case invalidSource(URL)
    case bitmapCreation(Int)
    case encoding(Int)
    var description: String {
        switch self {
        case .usage: return "Usage: scripts/make-icon.swift <destination-iconset> [source-png]"
        case .missingSource(let url): return "Icon source not found: \(url.path)"
        case .invalidSource(let url): return "Could not read the icon source: \(url.path)"
        case .bitmapCreation(let pixels): return "Could not create a bitmap for the \(pixels)-pixel icon."
        case .encoding(let pixels): return "Could not encode a PNG for the \(pixels)-pixel icon."
        }
    }
}

let arguments = CommandLine.arguments
guard (2...3).contains(arguments.count) else { throw IconError.usage }
let destination = URL(fileURLWithPath: arguments[1], isDirectory: true)
let source = URL(fileURLWithPath: arguments.count == 3 ? arguments[2] : "Support/Brand/AppIcon.png")
guard FileManager.default.fileExists(atPath: source.path) else { throw IconError.missingSource(source) }
guard let sourceImage = NSImage(contentsOf: source) else { throw IconError.invalidSource(source) }
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for retina in [false, true] {
        let pixels = size * (retina ? 2 : 1)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { throw IconError.bitmapCreation(pixels) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.interpolationQuality = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        sourceImage.draw(
            in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(retina ? "@2x" : "").png"
        guard let data = rep.representation(using: .png, properties: [:]) else { throw IconError.encoding(pixels) }
        try data.write(to: destination.appendingPathComponent(filename), options: .atomic)
    }
}
