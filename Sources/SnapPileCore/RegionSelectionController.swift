import AppKit

@MainActor
public final class RegionSelectionController {
    private var windows: [NSWindow] = []
    private var completion: ((CaptureSelection?) -> Void)?
    private var finished = false
    private weak var previousApplication: NSRunningApplication?
    private var cursorWasPushed = false
    private var observers: [NSObjectProtocol] = []
    private var screenFrames: [CGRect] = []

    public init() {}

    /// `agentReason` marks a selection that a coding agent requested.
    public func begin(agentReason: String? = nil, completion: @escaping (CaptureSelection?) -> Void) {
        cancel()
        self.completion = completion
        finished = false
        previousApplication = NSWorkspace.shared.frontmostApplication
        NSCursor.crosshair.push()
        cursorWasPushed = true
        screenFrames = NSScreen.screens.map(\.frame)
        // Key events reach only the key window, so Space state is shared across displays.
        let keyState = SelectionKeyState()
        for screen in NSScreen.screens {
            let view = SelectionOverlayView(screenFrame: screen.frame, keyState: keyState, agentReason: agentReason) {
                [weak self] result in
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
        // Without key focus Esc no longer reaches the overlay, and stale screen
        // frames would make the capture fail, so end the session instead.
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.cancel() }
            },
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main)
            { [weak self] _ in
                Task { @MainActor in
                    guard let self, NSScreen.screens.map(\.frame) != self.screenFrames else { return }
                    self.cancel()
                }
            },
        ]
    }

    public func cancel() { finish(nil) }

    private func finish(_ result: CaptureSelection?) {
        guard !finished else { return }
        finished = true
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
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

final class SelectionKeyState {
    var isSpaceHeld = false
}

final class SelectionOverlayView: NSView {
    private let screenFrame: CGRect
    private let displayID: CGDirectDisplayID
    private let keyState: SelectionKeyState
    private let agentReason: String?
    private let report: (CaptureSelection?) -> Void
    private var drag = SelectionDragState(bounds: .zero)
    var currentMousePoint: (() -> CGPoint)?

    init(
        screenFrame: CGRect, keyState: SelectionKeyState = SelectionKeyState(), agentReason: String? = nil,
        report: @escaping (CaptureSelection?) -> Void
    ) {
        self.screenFrame = screenFrame
        self.keyState = keyState
        self.agentReason = agentReason
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
        var lines: [(String, NSFont)] = []
        if let agentReason {
            lines.append((L10n.text("A coding agent requests a screenshot"), .boldSystemFont(ofSize: 15)))
            if !agentReason.isEmpty { lines.append((agentReason, .systemFont(ofSize: 14))) }
        }
        lines.append((L10n.text("Select area  ·  Space to move  ·  Esc to cancel"), .systemFont(ofSize: 13)))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let texts = lines.map { text, font in
            NSAttributedString(
                string: text, attributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: centered])
        }
        let maxWidth = min(720, bounds.width - 40)
        let sizes = texts.map {
            $0.boundingRect(with: NSSize(width: maxWidth, height: 200), options: .usesLineFragmentOrigin).size
        }
        let spacing: CGFloat = 8
        var top = (bounds.height + sizes.reduce(0) { $0 + $1.height } + spacing * CGFloat(sizes.count - 1)) / 2
        for (text, size) in zip(texts, sizes) {
            top -= size.height
            text.draw(
                with: CGRect(x: (bounds.width - size.width) / 2, y: top, width: size.width, height: size.height),
                options: .usesLineFragmentOrigin)
            top -= spacing
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        // Space may have been pressed or released while another display's window was key.
        drag.setMoving(keyState.isSpaceHeld, at: point)
        drag.begin(at: point)
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
            keyState.isSpaceHeld = true
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
            keyState.isSpaceHeld = false
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
