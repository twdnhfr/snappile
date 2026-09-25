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
        keyState.windows = PickableWindow.onScreen(
            excludingPID: ProcessInfo.processInfo.processIdentifier,
            primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        keyState.onChange = { [weak self] in
            for window in self?.windows ?? [] { window.contentView?.needsDisplay = true }
        }
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
    /// A shorter press toggles the mode; a longer one only moves the selection.
    static let tapDuration: TimeInterval = 0.3

    var isSpaceHeld = false
    var isMouseDown = false
    /// Tapping Space switches between area and window selection.
    var picksWindows = false
    var windows: [PickableWindow] = []
    var hoveredWindow: PickableWindow?
    var onChange: (() -> Void)?
    fileprivate var spacePressedAt: TimeInterval = 0
    fileprivate var spaceUsedForMoving = false
}

struct PickableWindow: Equatable {
    let id: CGWindowID
    let app: String
    /// Global AppKit coordinates, whose origin is at the bottom left.
    let frame: CGRect

    /// Visible app windows, front to back.
    static func onScreen(excludingPID pid: pid_t, primaryHeight: CGFloat) -> [PickableWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return windows(from: (info as? [[String: Any]]) ?? [], excludingPID: pid, primaryHeight: primaryHeight)
    }

    /// CGWindowList bounds start at the top left of the primary display.
    static func windows(
        from info: [[String: Any]], excludingPID pid: pid_t, primaryHeight: CGFloat
    )
        -> [PickableWindow]
    {
        info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != pid,
                (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                bounds.width >= 40, bounds.height >= 40
            else { return nil }
            return PickableWindow(
                id: id, app: entry[kCGWindowOwnerName as String] as? String ?? "",
                frame: CGRect(
                    x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height))
        }
    }
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
        // Hovering highlights windows on every display, not only in the key window.
        addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0, alpha: 0.42).setFill()
        bounds.fill()
        if keyState.picksWindows {
            drawHoveredWindow()
            drawInstruction()
            return
        }
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
        lines.append(
            (
                keyState.picksWindows
                    ? L10n.text("Click a window  ·  Tap Space for area  ·  Esc to cancel")
                    : L10n.text("Select area  ·  Tap Space for windows  ·  Hold Space to move  ·  Esc to cancel"),
                .systemFont(ofSize: 13)
            ))
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
        let height = sizes.reduce(0) { $0 + $1.height } + spacing * CGFloat(sizes.count - 1)
        let width = sizes.map(\.width).max() ?? 0
        // Keeps the text readable on top of a highlighted window.
        NSColor(calibratedWhite: 0, alpha: 0.55).setFill()
        NSBezierPath(
            roundedRect: CGRect(
                x: (bounds.width - width) / 2 - 16, y: (bounds.height - height) / 2 - 10, width: width + 32,
                height: height + 20),
            xRadius: 10, yRadius: 10
        ).fill()
        var top = (bounds.height + height) / 2
        for (text, size) in zip(texts, sizes) {
            top -= size.height
            text.draw(
                with: CGRect(x: (bounds.width - size.width) / 2, y: top, width: size.width, height: size.height),
                options: .usesLineFragmentOrigin)
            top -= spacing
        }
    }

    private func drawHoveredWindow() {
        guard let hovered = keyState.hoveredWindow else { return }
        let rect = hovered.frame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY).intersection(bounds)
        guard !rect.isNull, !rect.isEmpty else { return }
        NSGraphicsContext.current?.cgContext.clear(rect)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        rect.fill()
        let border = NSBezierPath(rect: rect.insetBy(dx: 1.5, dy: 1.5))
        border.lineWidth = 3
        NSColor.controlAccentColor.setStroke()
        border.stroke()
        let label = NSAttributedString(
            string: hovered.app,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.white])
        let size = label.size()
        let badge = CGRect(
            x: rect.minX + 10, y: rect.maxY - size.height - 18, width: size.width + 16, height: size.height + 8)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
        label.draw(at: CGPoint(x: badge.minX + 8, y: badge.minY + 4))
    }

    private func hover(at point: CGPoint) {
        let global = CGPoint(x: point.x + screenFrame.minX, y: point.y + screenFrame.minY)
        let hovered = keyState.windows.first { $0.frame.contains(global) }
        guard hovered != keyState.hoveredWindow else { return }
        keyState.hoveredWindow = hovered
        needsDisplay = true
        keyState.onChange?()
    }

    private func windowSelection(_ picked: PickableWindow) -> CaptureSelection {
        CaptureSelection(
            displayID: displayID, screenFrame: screenFrame, rect: picked.frame.intersection(screenFrame),
            windowID: picked.id)
    }

    override func mouseMoved(with event: NSEvent) {
        guard keyState.picksWindows else { return }
        hover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        keyState.isMouseDown = true
        if keyState.isSpaceHeld { keyState.spaceUsedForMoving = true }
        let point = convert(event.locationInWindow, from: nil)
        if keyState.picksWindows {
            hover(at: point)
            if let picked = keyState.hoveredWindow { report(windowSelection(picked)) }
            return
        }
        // Space may have been pressed or released while another display's window was key.
        drag.setMoving(keyState.isSpaceHeld, at: point)
        drag.begin(at: point)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard !keyState.picksWindows else { return }
        drag.update(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        keyState.isMouseDown = false
        guard !keyState.picksWindows else { return }
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
            if !event.isARepeat {
                keyState.spacePressedAt = event.timestamp
                keyState.spaceUsedForMoving = keyState.isMouseDown
            }
            keyState.isSpaceHeld = true
            drag.setMoving(true, at: currentMousePoint?() ?? windowMousePoint())
            needsDisplay = true
        } else if event.keyCode == 36, keyState.picksWindows {
            if let picked = keyState.hoveredWindow { report(windowSelection(picked)) }
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
            if !keyState.spaceUsedForMoving, !keyState.isMouseDown,
                event.timestamp - keyState.spacePressedAt < SelectionKeyState.tapDuration
            {
                keyState.picksWindows.toggle()
                keyState.hoveredWindow = nil
                if keyState.picksWindows { hover(at: currentMousePoint?() ?? windowMousePoint()) }
                keyState.onChange?()
            }
            needsDisplay = true
        } else {
            super.keyUp(with: event)
        }
    }
    private func windowMousePoint() -> CGPoint {
        convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
    }
}
