import AppKit
import Carbon
import Combine
import SnapPileCore
import SwiftUI

@main
enum SnapPileMain {
    @MainActor static func main() {
        // Coding agents launch the bundled executable as their MCP server.
        if CommandLine.arguments.dropFirst().first == "mcp" {
            MCPServer().run()
            return
        }
        let app = NSApplication.shared
        if let bundleID = Bundle.main.bundleIdentifier,
            let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
        {
            other.activate(options: [])
            return
        }
        app.setActivationPolicy(.accessory)
        let delegate = AppController()
        app.delegate = delegate
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: L10n.text("Quit SnapPile"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let menuItem = NSMenuItem()
        menuItem.submenu = appMenu
        mainMenu.addItem(menuItem)
        let editMenu = NSMenu(title: L10n.text("Edit"))
        for (title, action, key) in [
            (L10n.text("Copy"), "copy:", "c"), (L10n.text("Paste"), "paste:", "v"),
            (L10n.text("Select All"), "selectAll:", "a"),
        ] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: L10n.text("Edit"), action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        // NSWindow handles ⌘W and ⌘M only through menu items.
        let windowMenu = NSMenu(title: L10n.text("Window"))
        windowMenu.addItem(
            withTitle: L10n.text("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(
            withTitle: L10n.text("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem(title: L10n.text("Window"), action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        app.mainMenu = mainMenu
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

private enum CaptureOutcome {
    case captured(UUID)
    case cancelled
    case failed(String)
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    let settings = AppSettings()
    let store = ScreenshotStore()
    let captureService = ScreenCaptureService()
    let selection = RegionSelectionController()
    @Published var message: String?
    @Published var messageIsError = false
    @Published var isCapturing = false
    @Published var isExpanded = false
    @Published private(set) var selectedScreenshotID: UUID?
    @Published var screenPermission = false
    @Published var inputPermission = false
    @Published var optionMonitoringIssue: String?
    @Published var shortcutError: String?
    @Published var agentAccessError: String?
    private var subscriptions = Set<AnyCancellable>()
    private var expiryTimer: Timer?
    private var messageTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var statusController: StatusItemController?
    private var stackController: StackPanelController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var previewWindow: NSWindow?
    private var previewID: UUID?
    private var hotKeys: HotKeyController?
    private var agentServer: AgentSocketServer?
    private var isTerminating = false
    private var captureGeneration = UUID()
    private var previousStackIDs: [UUID] = []

    override init() {
        super.init()
        store.$items.map { $0.map(\.id) }.removeDuplicates().sink { [weak self] ids in
            self?.reconcileStackSelection(ids)
        }.store(in: &subscriptions)
    }

    var selectedStackItem: ScreenshotItem? {
        selectedScreenshotID.flatMap { store.item(id: $0) } ?? store.items.first
    }

    var stackPosition: Int {
        guard let item = selectedStackItem, let index = store.items.firstIndex(where: { $0.id == item.id }) else {
            return 0
        }
        return index + 1
    }

    private func reconcileStackSelection(_ ids: [UUID]) {
        defer { previousStackIDs = ids }
        guard let newest = ids.first else {
            selectedScreenshotID = nil
            return
        }
        if !previousStackIDs.contains(newest) {
            selectedScreenshotID = newest
        } else if let selectedScreenshotID, ids.contains(selectedScreenshotID) {
            return
        } else {
            let oldIndex = selectedScreenshotID.flatMap { previousStackIDs.firstIndex(of: $0) } ?? 0
            selectedScreenshotID = ids[min(oldIndex, ids.count - 1)]
        }
    }

    func browseStack(by direction: Int) {
        guard !isExpanded, store.items.count > 1, direction != 0 else { return }
        let count = store.items.count
        let index = max(0, stackPosition - 1)
        let next = (index + direction % count + count) % count
        selectedScreenshotID = store.items[next].id
        stackController?.reposition()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TemporaryScreenshotFiles.shared.removeExpired()
        store.maxItems = settings.maxItems
        store.expiryMinutes = settings.expiryMinutes
        hotKeys = HotKeyController(onTrigger: { [weak self] in self?.beginCapture() })
        hotKeys?.doubleOptionEnabled = settings.doubleOptionEnabled
        registerShortcut()
        statusController = StatusItemController(model: self)
        stackController = StackPanelController(model: self)
        settings.$maxItems.dropFirst().sink { [weak self] value in self?.store.maxItems = value }.store(
            in: &subscriptions)
        settings.$expiryMinutes.dropFirst().sink { [weak self] value in
            self?.store.expiryMinutes = value
            self?.store.removeExpired()
        }.store(in: &subscriptions)
        settings.$side.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.stackController?.reposition() }
        }.store(in: &subscriptions)
        settings.$agentAccessEnabled.removeDuplicates().sink { [weak self] enabled in
            self?.setAgentAccess(enabled)
        }.store(in: &subscriptions)
        settings.$doubleOptionEnabled.dropFirst().sink { [weak self] value in
            self?.hotKeys?.doubleOptionEnabled = value
            self?.refreshPermissions()
        }.store(in: &subscriptions)
        store.$items.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let items = self.store.items
                self.statusController?.updateCount(items.count)
                self.stackController?.reposition()
                if items.isEmpty {
                    self.stackController?.hide()
                    self.isExpanded = false
                }
                if let id = self.previewID, !items.contains(where: { $0.id == id }) { self.closePreview() }
            }
        }.store(in: &subscriptions)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.store.removeExpired()
                TemporaryScreenshotFiles.shared.removeExpired()
                if self.settingsWindow?.isVisible == true || self.onboardingWindow?.isVisible == true {
                    self.refreshPermissions()
                }
            }
        }
        if let expiryTimer { RunLoop.main.add(expiryTimer, forMode: .common) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshPermissions), name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        refreshPermissions()
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            insertDemoImages()
            showStack()
            showOnboarding()
        } else if !settings.hasCompletedOnboarding || !screenPermission {
            showOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        refreshPermissions()
        guard !flag else { return true }
        if !settings.hasCompletedOnboarding || !screenPermission {
            showOnboarding()
        } else if store.items.isEmpty {
            showSettings()
        } else {
            showStack()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        captureGeneration = UUID()
        captureTask?.cancel()
        messageTask?.cancel()
        selection.cancel()
        expiryTimer?.invalidate()
        hotKeys?.stop()
        agentServer?.stop()
        statusController?.shutdown()
        stackController?.shutdown()
        closePreview()
        store.removeAll(includingPinned: true)
        TemporaryScreenshotFiles.shared.removeAll()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc func refreshPermissions() {
        screenPermission = captureService.hasPermission
        hotKeys?.refreshOptionMonitoring()
        inputPermission = hotKeys?.hasInputMonitoringPermission ?? false
        optionMonitoringIssue = hotKeys?.optionMonitoringError
    }
    @objc private func didWake() {
        store.removeExpired()
        TemporaryScreenshotFiles.shared.removeExpired()
        refreshPermissions()
    }
    @objc private func willSleep() { selection.cancel() }

    // The first request returns immediately while macOS shows its own prompt, so
    // System Settings opens only on later requests instead of covering that prompt.
    func requestScreenPermission() {
        let promptShown = settings.hasRequestedScreenPermission
        settings.hasRequestedScreenPermission = true
        _ = captureService.requestPermission()
        refreshPermissions()
        if !screenPermission && promptShown { openPrivacy("Privacy_ScreenCapture") }
    }
    func requestInputPermission() {
        let promptShown = settings.hasRequestedInputPermission
        settings.hasRequestedInputPermission = true
        hotKeys?.requestInputMonitoringPermission()
        refreshPermissions()
        if !inputPermission && promptShown { openPrivacy("Privacy_ListenEvent") }
    }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
    func registerShortcut() {
        do {
            try hotKeys?.register(keyCode: settings.shortcutKeyCode, modifiers: settings.shortcutModifiers)
            shortcutError = nil
        } catch { shortcutError = error.localizedDescription }
    }
    func applyShortcut(keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            shortcutError = L10n.text("Choose at least ⌘, ⌃, or ⌥.")
            return false
        }
        do {
            try hotKeys?.register(keyCode: keyCode, modifiers: modifiers)
            settings.shortcutKeyCode = keyCode
            settings.shortcutModifiers = modifiers
            shortcutError = nil
            return true
        } catch {
            shortcutError = error.localizedDescription
            return false
        }
    }

    func beginCapture() { startCapture(agentReason: nil, completion: nil) }

    /// Reports exactly once whether the user captured an image, cancelled, or no capture could start.
    private func startCapture(agentReason: String?, completion: ((CaptureOutcome) -> Void)?) {
        guard !isCapturing else {
            completion?(.failed(L10n.text("SnapPile is already capturing.")))
            return
        }
        guard !isTerminating else {
            completion?(.cancelled)
            return
        }
        statusController?.close()
        refreshPermissions()
        guard screenPermission else {
            showOnboarding()
            notify(L10n.text("Allow screen recording first."), error: true)
            completion?(.failed(L10n.text("Allow screen recording first.")))
            return
        }
        if store.items.count >= settings.maxItems && store.items.allSatisfy(\.isPinned) {
            notify(L10n.text("The pile is full. Unpin or delete an image."), error: true)
            showStack()
            completion?(.failed(L10n.text("The pile is full. Unpin or delete an image.")))
            return
        }
        isCapturing = true
        let generation = UUID()
        captureGeneration = generation
        let stackWasVisible = stackController?.isVisible == true
        let hiddenWindows = [settingsWindow, onboardingWindow, previewWindow].compactMap { $0 }.filter(\.isVisible)
        stackController?.hide()
        for window in hiddenWindows { window.orderOut(nil) }
        selection.begin(agentReason: agentReason) { [weak self] result in
            guard let self, !self.isTerminating, self.captureGeneration == generation else {
                completion?(.cancelled)
                return
            }
            guard let result else {
                self.isCapturing = false
                self.restoreWindows(hiddenWindows)
                if stackWasVisible { self.showStack() }
                completion?(.cancelled)
                return
            }
            self.captureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var outcome = CaptureOutcome.cancelled
                defer { completion?(outcome) }
                do {
                    let image = try await self.captureService.capture(selection: result)
                    guard !Task.isCancelled, !self.isTerminating, self.captureGeneration == generation else { return }
                    let id = try self.store.add(
                        pngData: image.pngData, pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight)
                    outcome = .captured(id)
                    self.stackController?.setScreen(displayID: result.displayID)
                    self.isExpanded = false
                    self.notify(
                        agentReason == nil
                            ? L10n.text("In the pile · ready to drag") : L10n.text("In the pile · sent to the agent"))
                } catch {
                    outcome = .failed(error.localizedDescription)
                    self.notify(error.localizedDescription, error: true)
                    // Restore first so an already open Settings window keeps its state.
                    self.restoreWindows(hiddenWindows)
                    if self.store.items.isEmpty { self.showSettings() }
                }
                self.isCapturing = false
                self.restoreWindows(hiddenWindows)
                self.showStack()
            }
        }
    }

    private func setAgentAccess(_ enabled: Bool) {
        agentServer?.stop()
        agentServer = nil
        agentAccessError = nil
        guard enabled, !isTerminating else { return }
        let server = AgentSocketServer()
        do {
            try server.start { [weak self] request in
                guard let self else { return .failure(AgentBridgeError.notRunning.localizedDescription) }
                return await self.handleAgentRequest(request)
            }
            agentServer = server
        } catch {
            agentAccessError = error.localizedDescription
        }
    }

    private func handleAgentRequest(_ request: AgentRequest) async -> AgentResponse {
        switch request.command {
        case .latest:
            guard let item = store.items.first else { return .failure(L10n.text("The pile is empty.")) }
            return .image(item.pngData, pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight)
        case .capture:
            let reason = String((request.reason ?? "").prefix(200))
            let outcome = await withCheckedContinuation { continuation in
                startCapture(agentReason: reason) { continuation.resume(returning: $0) }
            }
            switch outcome {
            case .captured(let id):
                guard let item = store.item(id: id) else {
                    return .failure(L10n.text("This image is no longer in the pile."))
                }
                return .image(item.pngData, pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight)
            case .cancelled: return .failure(L10n.text("The user cancelled the screenshot."))
            case .failed(let message): return .failure(message)
            }
        }
    }

    /// Registers the bundled executable as a user-scoped MCP server in Claude Code.
    var agentSetupCommand: String {
        let path = Bundle.main.executablePath ?? "/Applications/SnapPile.app/Contents/MacOS/SnapPile"
        return "claude mcp add --scope user snappile -- '\(path.replacingOccurrences(of: "'", with: "'\\''"))' mcp"
    }
    func copyAgentSetupCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(agentSetupCommand, forType: .string)
        notify(L10n.text("Setup command copied"))
    }
    private func restoreWindows(_ windows: [NSWindow]) {
        // A window may have been closed meanwhile, e.g. a preview whose item expired.
        let current = [settingsWindow, onboardingWindow, previewWindow]
        for window in windows where current.contains(where: { $0 === window }) {
            window.orderFront(nil)
        }
    }

    func showStack() {
        guard !store.items.isEmpty, !isCapturing else { return }
        stackController?.show()
    }
    func hideStack() { stackController?.hide() }
    func toggleExpanded() {
        isExpanded.toggle()
        stackController?.reposition()
        showStack()
    }
    func notify(_ text: String, error: Bool = false) {
        messageTask?.cancel()
        messageIsError = error
        message = text
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: error ? 8_000_000_000 : 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
    func copy(_ id: UUID) {
        guard let item = store.item(id: id) else { return }
        let copied = ImageTransfer.copy(item)
        notify(copied ? L10n.text("Image copied") : L10n.text("Copy failed"), error: !copied)
    }
    func save(_ id: UUID) {
        guard let item = store.item(id: id) else { return }
        ImageTransfer.save(item) { [weak self] result in
            switch result {
            case .success(let url): if url != nil { self?.notify(L10n.text("PNG saved")) }
            case .failure(let error): self?.notify(error.localizedDescription, error: true)
            }
        }
    }
    func delete(_ id: UUID) { store.remove(id: id) }
    func clearUnpinned() { store.removeAll(includingPinned: false) }
    func showOnboarding() {
        statusController?.close()
        refreshPermissions()
        if onboardingWindow == nil {
            let height = min(740, (Self.activeScreen?.visibleFrame.height ?? 800) - 60)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: height), styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = L10n.text("Welcome to SnapPile")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: OnboardingView(model: self))
            Self.center(window)
            onboardingWindow = window
        }
        settingsWindow?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
    func dismissOnboarding() {
        // "Later" counts as completed; a missing screen permission still reopens onboarding on launch.
        settings.hasCompletedOnboarding = true
        onboardingWindow?.orderOut(nil)
    }
    func finishOnboardingAndCapture() {
        refreshPermissions()
        guard screenPermission else {
            notify(L10n.text("Screen recording permission is still required."), error: true)
            return
        }
        settings.hasCompletedOnboarding = true
        dismissOnboarding()
        beginCapture()
    }
    func showSettings() {
        statusController?.close()
        onboardingWindow?.orderOut(nil)
        refreshPermissions()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 710),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "SnapPile"
            window.isReleasedWhenClosed = false
            Self.center(window)
            settingsWindow = window
        }
        if settingsWindow?.isVisible != true && settingsWindow?.isMiniaturized != true {
            // Start from the active shortcut: an unapplied or rejected draft must not survive closing the window.
            registerShortcut()
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(model: self))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func preview(_ id: UUID) {
        guard store.item(id: id) != nil else { return }
        closePreview()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 630),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L10n.text("SnapPile · Preview")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 480, height: 360)
        window.contentView = NSHostingView(rootView: PreviewView(model: self, itemID: id))
        Self.center(window)
        previewWindow = window
        previewID = id
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            settings.hasCompletedOnboarding = true
            return
        }
        guard window === previewWindow else { return }
        window.contentView = nil
        previewWindow = nil
        previewID = nil
    }
    /// The display under the pointer, where the user just clicked the menu or pile.
    private static var activeScreen: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    }
    /// Like NSWindow.center(), which always picks the window's current screen.
    private static func center(_ window: NSWindow) {
        guard let visible = activeScreen?.visibleFrame else { return window.center() }
        let size = window.frame.size
        window.setFrameOrigin(
            CGPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.minY + max(0, visible.height - size.height) * 2 / 3).rounded()))
    }
    private func closePreview() {
        let window = previewWindow
        previewWindow = nil
        previewID = nil
        window?.contentView = nil
        window?.close()
    }
}
