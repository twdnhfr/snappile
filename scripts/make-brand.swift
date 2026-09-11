import AppKit
import CoreText

// Regenerates the portable README wordmarks from the same flat mark used in the app.
// Letter outlines are embedded so viewers do not need the design font installed.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let markURL = root.appendingPathComponent("Sources/SnapPile/Resources/BrandMark.svg")
let destination = root.appendingPathComponent("Support/Brand", isDirectory: true)
let mark = try String(contentsOf: markURL, encoding: .utf8)
guard let contentStart = mark.firstIndex(of: ">"), let contentEnd = mark.range(of: "</svg>") else {
    fatalError("BrandMark.svg enthält kein SVG-Dokument.")
}
let markContent = String(mark[mark.index(after: contentStart)..<contentEnd.lowerBound])
let baseFont = NSFont.systemFont(ofSize: 84, weight: .semibold)
let font = NSFont(descriptor: baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor, size: 84)!
let line = CTLineCreateWithAttributedString(
    NSAttributedString(string: "SnapPile", attributes: [.font: font, .kern: -1.5]))
let letters = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
    for index in 0..<count {
        if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) {
            letters.addPath(
                glyph, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
        }
    }
}
let bounds = letters.boundingBoxOfPath
var transform = CGAffineTransform(
    a: 1, b: 0, c: 0, d: -1, tx: 181 - bounds.minX, ty: 80 + bounds.midY)
let positioned = letters.copy(using: &transform)!
func number(_ value: CGFloat) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
}
func point(_ value: CGPoint) -> String { "\(number(value.x)) \(number(value.y))" }
var path = ""
positioned.applyWithBlock { pointer in
    let element = pointer.pointee
    switch element.type {
    case .moveToPoint: path += "M\(point(element.points[0]))"
    case .addLineToPoint: path += "L\(point(element.points[0]))"
    case .addQuadCurveToPoint: path += "Q\(point(element.points[0])) \(point(element.points[1]))"
    case .addCurveToPoint:
        path += "C\(point(element.points[0])) \(point(element.points[1])) \(point(element.points[2]))"
    case .closeSubpath: path += "Z"
    @unknown default: break
    }
}
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let width = Int(ceil(positioned.boundingBoxOfPath.maxX + 6))
for (variant, color) in [("light", "#193A37"), ("dark", "#F0F8F5")] {
    let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="160" viewBox="0 0 \(width) 160">
          <title>SnapPile</title>
          <svg x="0" y="0" width="160" height="160" viewBox="0 0 128 128" fill="none">\(markContent)</svg>
          <path fill="\(color)" d="\(path)"/>
        </svg>
        """
    try (svg + "\n").write(
        to: destination.appendingPathComponent("snappile-logo-\(variant).svg"), atomically: true, encoding: .utf8)
}
