import AppKit
import Carbon
import Combine
import SnapPileCore
import SwiftUI

@main
enum SnapPileMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate(options: [])
            return
        }
        app.setActivationPolicy(.accessory)
        let delegate = AppController()
        app.delegate = delegate
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "SnapPile beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let menuItem = NSMenuItem(); menuItem.submenu = appMenu; mainMenu.addItem(menuItem)
        let editMenu = NSMenu(title: "Bearbeiten")
        for (title, action, key) in [("Kopieren", "copy:", "c"), ("Einfügen", "paste:", "v"), ("Alles auswählen", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Bearbeiten", action: nil, keyEquivalent: ""); editItem.submenu = editMenu; mainMenu.addItem(editItem)
        app.mainMenu = mainMenu
        app.run()
        withExtendedLifetime(delegate) {}
    }
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
    @Published var screenPermission = false
    @Published var inputPermission = false
    @Published var optionMonitoringIssue: String?
    @Published var shortcutError: String?
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
    private var isTerminating = false
    private var captureGeneration = UUID()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.maxItems = settings.maxItems
        store.expiryMinutes = settings.expiryMinutes
        hotKeys = HotKeyController(onTrigger: { [weak self] in self?.beginCapture() })
        hotKeys?.doubleOptionEnabled = settings.doubleOptionEnabled
        registerShortcut()
        statusController = StatusItemController(model: self)
        stackController = StackPanelController(model: self)
        settings.$maxItems.dropFirst().sink { [weak self] value in self?.store.maxItems = value }.store(in: &subscriptions)
        settings.$expiryMinutes.dropFirst().sink { [weak self] value in
            self?.store.expiryMinutes = value; self?.store.removeExpired()
        }.store(in: &subscriptions)
        settings.$side.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.stackController?.reposition() }
        }.store(in: &subscriptions)
        settings.$doubleOptionEnabled.dropFirst().sink { [weak self] value in self?.hotKeys?.doubleOptionEnabled = value; self?.refreshPermissions() }.store(in: &subscriptions)
        store.$items.sink { [weak self] items in
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusController?.updateCount(items.count)
                if items.isEmpty { self.stackController?.hide(); self.isExpanded = false }
                if let id = self.previewID, !items.contains(where: { $0.id == id }) { self.closePreview() }
            }
        }.store(in: &subscriptions)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.removeExpired() }
        }
        if let expiryTimer { RunLoop.main.add(expiryTimer, forMode: .common) }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPermissions), name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        refreshPermissions()
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            insertDemoImages(); showStack(); showOnboarding()
        } else if !settings.hasCompletedOnboarding || !screenPermission {
            showOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if !settings.hasCompletedOnboarding || !screenPermission { showOnboarding() }
        else if store.items.isEmpty { showSettings() } else { showStack() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        captureGeneration = UUID()
        captureTask?.cancel(); messageTask?.cancel(); selection.cancel()
        expiryTimer?.invalidate(); hotKeys?.stop(); statusController?.shutdown(); stackController?.hide(); closePreview()
        store.removeAll(includingPinned: true)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc func refreshPermissions() {
        screenPermission = captureService.hasPermission
        hotKeys?.refreshOptionMonitoring()
        inputPermission = hotKeys?.hasInputMonitoringPermission ?? false
        optionMonitoringIssue = hotKeys?.optionMonitoringError
    }
    @objc private func didWake() { store.removeExpired(); refreshPermissions() }
    @objc private func willSleep() { selection.cancel() }

    func requestScreenPermission() {
        _ = captureService.requestPermission()
        refreshPermissions()
        if !screenPermission { openPrivacy("Privacy_ScreenCapture") }
    }
    func requestInputPermission() {
        hotKeys?.requestInputMonitoringPermission(); refreshPermissions()
        if !inputPermission { openPrivacy("Privacy_ListenEvent") }
    }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    func registerShortcut() {
        do {
            try hotKeys?.register(keyCode: settings.shortcutKeyCode, modifiers: settings.shortcutModifiers)
            shortcutError = nil
        } catch { shortcutError = error.localizedDescription }
    }
    func applyShortcut(keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            shortcutError = "Bitte mindestens ⌘, ⌃ oder ⌥ wählen."; return false
        }
        do {
            try hotKeys?.register(keyCode: keyCode, modifiers: modifiers)
            settings.shortcutKeyCode = keyCode; settings.shortcutModifiers = modifiers
            shortcutError = nil; return true
        } catch { shortcutError = error.localizedDescription; return false }
    }

    func beginCapture() {
        guard !isCapturing, !isTerminating else { return }
        statusController?.close()
        refreshPermissions()
        guard screenPermission else {
            showOnboarding()
            notify("Bitte erlaube zuerst die Bildschirmaufnahme.", error: true)
            return
        }
        if store.items.count >= settings.maxItems && store.items.allSatisfy(\.isPinned) {
            notify("Der Stapel ist voll. Löse einen Pin oder lösche ein Bild.", error: true)
            showStack(); return
        }
        isCapturing = true
        let generation = UUID(); captureGeneration = generation
        stackController?.hide(); settingsWindow?.orderOut(nil); onboardingWindow?.orderOut(nil); previewWindow?.orderOut(nil)
        selection.begin { [weak self] result in
            guard let self, !self.isTerminating, self.captureGeneration == generation else { return }
            guard let result else { self.isCapturing = false; self.showStack(); return }
            self.captureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let image = try await self.captureService.capture(selection: result)
                    guard !Task.isCancelled, !self.isTerminating, self.captureGeneration == generation else { return }
                    _ = try self.store.add(pngData: image.pngData, pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight)
                    self.stackController?.setScreen(displayID: result.displayID)
                    self.isExpanded = false
                    self.notify("Im Stapel · bereit zum Ziehen")
                } catch {
                    self.notify(error.localizedDescription, error: true)
                    if self.store.items.isEmpty { self.showSettings() }
                }
                self.isCapturing = false
                self.showStack()
            }
        }
    }

    func showStack() {
        guard !store.items.isEmpty, !isCapturing else { return }
        stackController?.show()
    }
    func hideStack() { stackController?.hide() }
    func toggleExpanded() { isExpanded.toggle(); stackController?.reposition(); showStack() }
    func notify(_ text: String, error: Bool = false) {
        messageTask?.cancel(); messageIsError = error; message = text
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: error ? 8_000_000_000 : 3_000_000_000)
            guard !Task.isCancelled else { return }; self?.message = nil
        }
    }
    func copy(_ id: UUID) {
        guard let item = store.item(id: id) else { return }
        let copied = ImageTransfer.copy(item)
        notify(copied ? "Bild kopiert" : "Kopieren fehlgeschlagen", error: !copied)
    }
    func save(_ id: UUID) {
        guard let item = store.item(id: id) else { return }
        ImageTransfer.save(item) { [weak self] result in
            switch result {
            case .success(let url): if url != nil { self?.notify("PNG gespeichert") }
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
            let height = min(740, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:height),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.title = "Willkommen bei SnapPile"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView:OnboardingView(model:self))
            window.center(); onboardingWindow = window
        }
        settingsWindow?.orderOut(nil)
        NSApp.activate(ignoringOtherApps:true); onboardingWindow?.makeKeyAndOrderFront(nil)
    }
    func dismissOnboarding() { onboardingWindow?.orderOut(nil) }
    func finishOnboardingAndCapture() {
        refreshPermissions()
        guard screenPermission else { notify("Die Bildschirmfreigabe fehlt noch.",error:true); return }
        settings.hasCompletedOnboarding = true
        dismissOnboarding(); beginCapture()
    }
    func showSettings() {
        statusController?.close()
        onboardingWindow?.orderOut(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x:0,y:0,width:520,height:710), styleMask:[.titled,.closable,.miniaturizable], backing:.buffered, defer:false)
            window.title = "SnapPile"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model:self))
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func preview(_ id: UUID) {
        guard store.item(id:id) != nil else { return }
        closePreview()
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:880,height:630), styleMask:[.titled,.closable,.resizable,.miniaturizable], backing:.buffered, defer:false)
        window.title = "SnapPile · Vorschau"; window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width:480,height:360)
        window.contentView = NSHostingView(rootView: PreviewView(model:self, itemID:id))
        window.center(); previewWindow = window; previewID = id
        NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === previewWindow else { return }
        window.contentView = nil
        previewWindow = nil; previewID = nil
    }
    private func closePreview() {
        let window = previewWindow
        previewWindow = nil; previewID = nil
        window?.contentView = nil; window?.close()
    }
}
