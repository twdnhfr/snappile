import AppKit
import SnapPileCore
import SwiftUI

private final class FloatingPilePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StackPanelController {
    private let model: AppController
    private let panel: NSPanel
    private var displayID: CGDirectDisplayID?
    private var observer: NSObjectProtocol?
    private var scrollMonitor: Any?
    private var scrollGesture = StackScrollGesture()
    init(model: AppController) {
        self.model = model
        panel = FloatingPilePanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.title = L10n.text("SnapPile · Pile")
        let content = NSHostingView(
            rootView: StackView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        // The panel and its cards share one explicit layout; prevent AppKit from
        // resizing the panel again in response to SwiftUI's intrinsic size.
        content.sizingOptions = []
        panel.contentView = content
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        // Only intercept this app's floating stack. SwiftUI buttons and native
        // thumbnails route through the same monitor without taking key focus.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.isVisible else { return event }
            guard !self.model.isExpanded, self.model.store.items.count > 1,
                !self.model.isCapturing, NSEvent.pressedMouseButtons == 0
            else {
                self.scrollGesture.reset()
                return event
            }
            if let direction = self.scrollGesture.step(
                deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                precise: event.hasPreciseScrollingDeltas, phase: event.phase,
                momentumPhase: event.momentumPhase, timestamp: event.timestamp)
            {
                self.model.browseStack(by: direction)
            }
            return nil
        }
    }
    var isVisible: Bool { panel.isVisible }
    func setScreen(displayID: CGDirectDisplayID) { self.displayID = displayID }
    func show() {
        reposition()
        panel.orderFrontRegardless()
    }
    func hide() {
        scrollGesture.reset()
        panel.orderOut(nil)
    }
    func shutdown() {
        hide()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
    func reposition() {
        let screen =
            NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
            }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let width = StackLayout.width
        let contentHeight = StackLayout.height(itemCount: model.store.items.count, expanded: model.isExpanded)
        let height = min(contentHeight, visible.height - 24)
        let x = model.settings.side == .right ? visible.maxX - width - 2 : visible.minX + 2
        let y = max(visible.minY + 12, visible.midY - height / 2)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppController
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let hostingController: NSHostingController<FixedMenuPopoverView>
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?
    private var terminationObserver: Any?
    private var shuttingDown = false

    init(model: AppController) {
        self.model = model
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hostingController = NSHostingController(
            rootView: FixedMenuPopoverView(
                model: model, size: MenuPopoverLayout.size(itemCount: model.store.items.count)))
        super.init()
        if let button = item.button {
            button.image =
                BrandAssets.menuBarMark()
                ?? NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: L10n.text("SnapPile"))
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(toggle(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = L10n.text("SnapPile · temporary screenshot pile")
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        hostingController.sizingOptions = []
        popover.contentViewController = hostingController
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.shutdown() }
        }
    }
    func updateCount(_ count: Int) {
        item.button?.title = count > 0 ? " \(count)" : ""
        item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        item.button?.setAccessibilityLabel(
            L10n.format("SnapPile, %ld screenshots", count))
        if popover.isShown { applyContentSize() }
    }
    func close() {
        removeEventMonitors()
        popover.performClose(nil)
    }

    func shutdown() {
        guard !shuttingDown else { return }
        shuttingDown = true
        removeEventMonitors()
        popover.close()
        popover.contentViewController = nil
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func toggle(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            menu.addItem(makeMenuItem(L10n.text("Capture Area"), #selector(capture)))
            menu.addItem(makeMenuItem(L10n.text("Show Pile"), #selector(showStack)))
            menu.addItem(makeMenuItem(L10n.text("Settings…"), #selector(settings)))
            menu.addItem(makeMenuItem(L10n.text("Setup…"), #selector(onboarding)))
            menu.addItem(.separator())
            menu.addItem(
                withTitle: L10n.text("Quit SnapPile"), action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
            close()
            if let button = item.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            }
        } else if popover.isShown {
            close()
        } else if let button = item.button {
            model.refreshPermissions()
            showPopover(from: button)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        guard !popover.isShown else { return }

        applyContentSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installEventMonitors()
    }

    private func applyContentSize() {
        let size = MenuPopoverLayout.size(itemCount: model.store.items.count)
        // One explicit layout owner. Do not mix SwiftUI preferred-size tracking
        // with NSPopover sizing: repeated opens can otherwise grow the window.
        hostingController.rootView = FixedMenuPopoverView(model: model, size: size)
        hostingController.preferredContentSize = size
        hostingController.view.setFrameSize(size)
        popover.contentSize = size
        hostingController.view.layoutSubtreeIfNeeded()
    }

    private func installEventMonitors() {
        removeEventMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.close()
                return nil
            }
            guard let window = event.window else { return event }
            if window == self.item.button?.window { return event }
            var ancestor: NSWindow? = window
            while let current = ancestor {
                if current == self.popover.contentViewController?.view.window { return event }
                ancestor = current.parent
            }
            // NSMenu owns its event tracking; closing here would interrupt
            // actions from the popover's ellipsis menu.
            if window.level == .popUpMenu { return event }
            self.close()
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        globalClickMonitor = nil
        localEventMonitor = nil
    }

    func popoverDidClose(_ notification: Notification) {
        removeEventMonitors()
    }
    private func makeMenuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }
    @objc private func capture() { model.beginCapture() }
    @objc private func showStack() {
        model.showStack()
        close()
    }
    @objc private func settings() { model.showSettings() }
    @objc private func onboarding() { model.showOnboarding() }
}

enum MenuPopoverLayout {
    static func size(itemCount: Int) -> NSSize {
        let visibleCount = min(3, max(0, itemCount))
        return NSSize(width: 320, height: CGFloat(visibleCount == 0 ? 280 : 254 + 50 * (visibleCount - 1)))
    }
}

struct FixedMenuPopoverView: View {
    let model: AppController
    let size: NSSize
    var body: some View {
        MenuPopoverView(model: model)
            .frame(width: size.width, height: size.height, alignment: .top)
    }
}

struct PreviewView: View {
    @ObservedObject var model: AppController
    @ObservedObject var store: ScreenshotStore
    let itemID: UUID
    init(model: AppController, itemID: UUID) {
        self.model = model
        store = model.store
        self.itemID = itemID
    }
    var body: some View {
        if let item = store.item(id: itemID) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(L10n.format("%ld × %ld", item.pixelWidth, item.pixelHeight)).font(
                        .system(size: 12, weight: .medium)
                    )
                    .monospacedDigit()
                    Text(lifetimeText(item, minutes: model.settings.expiryMinutes)).font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.copy(itemID)
                    } label: {
                        Label(L10n.text("Copy"), systemImage: "doc.on.doc")
                    }.keyboardShortcut("c", modifiers: .command)
                    Button {
                        model.save(itemID)
                    } label: {
                        Label(L10n.text("Save"), systemImage: "square.and.arrow.down")
                    }.keyboardShortcut("s", modifiers: .command)
                    SmallIconButton(
                        item.isPinned ? L10n.text("Unpin") : L10n.text("Pin"),
                        symbol: item.isPinned ? "pin.fill" : "pin",
                        tint: item.isPinned ? pileAccent : .secondary
                    ) { store.togglePin(id: itemID) }
                    SmallIconButton(L10n.text("Delete"), symbol: "trash") { model.delete(itemID) }
                }.padding(14).background(.bar)
                FullImageView(pngData: item.pngData).frame(maxWidth: .infinity, maxHeight: .infinity).padding(18)
                    .background(.primary.opacity(0.035))
                HStack {
                    Text(
                        model.message
                            ?? L10n.text("Original resolution · Save or copy to share the full image.")
                    )
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    DraggableThumbnail(item: item, onClick: {}, onDragError: { model.notify($0, error: true) }).frame(
                        width: 62, height: 37
                    )
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.15)))
                    .help(L10n.text("Drag the original image from here into your chat"))
                    Text(L10n.text("Drag")).font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 14).padding(.vertical, 8)
            }
        } else {
            Text(L10n.text("This image is no longer in the pile.")).foregroundStyle(.secondary)
        }
    }
}

private struct FullImageView: NSViewRepresentable {
    let pngData: Data
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = NSImage(data: pngData)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setAccessibilityLabel(L10n.text("Screenshot at original resolution"))
        return view
    }
    func updateNSView(_ view: NSImageView, context: Context) {
        // Identity stays stable for the selected screenshot; avoid decoding on UI updates.
    }
    static func dismantleNSView(_ view: NSImageView, coordinator: ()) { view.image = nil }
}
