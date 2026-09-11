import AppKit

@MainActor
public final class RegionSelectionController {
    private var windows: [NSWindow] = []
    private var completion: ((CaptureSelection?) -> Void)?
    private var finished = false
    private weak var previousApplication: NSRunningApplication?
    private var cursorWasPushed = false

    public init() {}

    public func begin(completion: @escaping (CaptureSelection?) -> Void) {
        cancel()
        self.completion = completion
        finished = false
        previousApplication = NSWorkspace.shared.frontmostApplication
        NSCursor.crosshair.push(); cursorWasPushed = true
        for screen in NSScreen.screens {
            let view = SelectionOverlayView(screenFrame: screen.frame) { [weak self] result in
                self?.finish(result)
            }
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.level = .screenSaver; window.ignoresMouseEvents = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    public func cancel() { finish(nil) }

    private func finish(_ result: CaptureSelection?) {
        guard !finished else { return }
        finished = true
        windows.forEach { $0.orderOut(nil); $0.contentView = nil }
        windows.removeAll()
        if cursorWasPushed { NSCursor.pop(); cursorWasPushed = false }
        previousApplication?.activate(options: [])
        previousApplication = nil
        let callback = completion
        completion = nil
        callback?(result)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayView: NSView {
    private let screenFrame: CGRect
    private let displayID: CGDirectDisplayID
    private let report: (CaptureSelection?) -> Void
    private var start: CGPoint?
    private var current: CGRect = .zero

    init(screenFrame: CGRect, report: @escaping (CaptureSelection?) -> Void) {
        self.screenFrame = screenFrame
        self.displayID = (NSScreen.screens.first(where: { $0.frame == screenFrame })?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        self.report = report
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0, alpha: 0.42).setFill(); bounds.fill()
        guard !current.isEmpty else {
            drawInstruction(); return
        }
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.clear(current)
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.white.setStroke(); NSBezierPath(rect: current).stroke()
        let label = "\(Int(current.width.rounded())) × \(Int(current.height.rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white]
        (label as NSString).draw(at: CGPoint(x: current.minX + 8, y: current.maxY + 7), withAttributes: attrs)
    }

    private func drawInstruction() {
        let text = "Bereich auswählen  ·  Esc abbrechen"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); current = .zero; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        current = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                         width: abs(point.x-start.x), height: abs(point.y-start.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event); start = nil
        guard current.width >= 2, current.height >= 2 else { return }
        report(CaptureSelection(displayID: displayID, screenFrame: screenFrame,
                                rect: current.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { report(nil) }
        else if event.keyCode == 36, current.width >= 2, current.height >= 2 {
            report(CaptureSelection(displayID: displayID, screenFrame: screenFrame,
                                    rect: current.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)))
        } else { super.keyDown(with: event) }
    }
    private func clamped(_ p: CGPoint) -> CGPoint { CGPoint(x: min(max(0,p.x), bounds.width), y: min(max(0,p.y), bounds.height)) }
}
