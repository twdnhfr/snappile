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
        NSCursor.crosshair.push()
        cursorWasPushed = true
        for screen in NSScreen.screens {
            let view = SelectionOverlayView(screenFrame: screen.frame) { [weak self] result in
                self?.finish(result)
            }
            let window = SelectionWindow(
                contentRect: screen.frame, styleMask: .borderless,
                backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = false
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
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        if cursorWasPushed {
            NSCursor.pop()
            cursorWasPushed = false
        }
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

final class SelectionOverlayView: NSView {
    private let screenFrame: CGRect
    private let displayID: CGDirectDisplayID
    private let report: (CaptureSelection?) -> Void
    private var drag = SelectionDragState(bounds: .zero)
    var currentMousePoint: (() -> CGPoint)?

    init(screenFrame: CGRect, report: @escaping (CaptureSelection?) -> Void) {
        self.screenFrame = screenFrame
        self.displayID =
            (NSScreen.screens.first(where: { $0.frame == screenFrame })?.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        self.report = report
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        drag = SelectionDragState(bounds: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0, alpha: 0.42).setFill()
        bounds.fill()
        guard !drag.current.isEmpty else {
            drawInstruction()
            return
        }
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.clear(drag.current)
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.white.setStroke()
        NSBezierPath(rect: drag.current).stroke()
        let label = "\(Int(drag.current.width.rounded())) × \(Int(drag.current.height.rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white,
        ]
        (label as NSString).draw(at: CGPoint(x: drag.current.minX + 8, y: drag.current.maxY + 7), withAttributes: attrs)
    }

    private func drawInstruction() {
        let text = "Bereich auswählen  ·  Leertaste verschieben  ·  Esc abbrechen"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        drag.begin(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        drag.update(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        drag.end()
        guard drag.current.width >= 2, drag.current.height >= 2 else { return }
        report(
            CaptureSelection(
                displayID: displayID, screenFrame: screenFrame,
                rect: drag.current.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            report(nil)
        } else if event.keyCode == 49 {
            drag.setMoving(true, at: currentMousePoint?() ?? windowMousePoint())
            needsDisplay = true
        } else if event.keyCode == 36, drag.current.width >= 2, drag.current.height >= 2 {
            report(
                CaptureSelection(
                    displayID: displayID, screenFrame: screenFrame,
                    rect: drag.current.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)))
        } else {
            super.keyDown(with: event)
        }
    }
    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            drag.setMoving(false, at: currentMousePoint?() ?? windowMousePoint())
            needsDisplay = true
        } else {
            super.keyUp(with: event)
        }
    }
    private func windowMousePoint() -> CGPoint {
        convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
    }
}
