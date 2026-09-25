import AppKit
import Carbon
import Combine

public enum StackSide: String, CaseIterable, Identifiable {
    case left, right
    public var id: String { rawValue }
    public var label: String { self == .left ? L10n.text("Left") : L10n.text("Right") }
}

@MainActor
public final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published public var expiryMinutes: Int { didSet { defaults.set(expiryMinutes, forKey: "expiryMinutes") } }
    @Published public var maxItems: Int { didSet { defaults.set(maxItems, forKey: "maxItems") } }
    @Published public var side: StackSide { didSet { defaults.set(side.rawValue, forKey: "stackSide") } }
    @Published public var doubleOptionEnabled: Bool {
        didSet { defaults.set(doubleOptionEnabled, forKey: "doubleOptionEnabled") }
    }
    @Published public var shortcutKeyCode: UInt32 {
        didSet { defaults.set(Int(shortcutKeyCode), forKey: "shortcutKeyCode") }
    }
    @Published public var shortcutModifiers: UInt32 {
        didSet { defaults.set(Int(shortcutModifiers), forKey: "shortcutModifiers") }
    }
    /// Lets local coding agents request captures through a Unix socket; off by default.
    @Published public var agentAccessEnabled: Bool {
        didSet { defaults.set(agentAccessEnabled, forKey: "agentAccessEnabled") }
    }
    /// Lets agents capture whole displays without a selection; requires `agentAccessEnabled`.
    @Published public var agentScreenCaptureEnabled: Bool {
        didSet { defaults.set(agentScreenCaptureEnabled, forKey: "agentScreenCaptureEnabled") }
    }
    @Published public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    /// macOS shows its consent prompt only for the first request of each permission.
    public var hasRequestedScreenPermission: Bool {
        get { defaults.bool(forKey: "hasRequestedScreenPermission") }
        set { defaults.set(newValue, forKey: "hasRequestedScreenPermission") }
    }
    public var hasRequestedInputPermission: Bool {
        get { defaults.bool(forKey: "hasRequestedInputPermission") }
        set { defaults.set(newValue, forKey: "hasRequestedInputPermission") }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "expiryMinutes": 30, "maxItems": 20, "stackSide": "right", "doubleOptionEnabled": true,
            "shortcutKeyCode": 1, "shortcutModifiers": Int(controlKey | optionKey),
        ])
        expiryMinutes =
            [5, 15, 30, 60, 120].contains(defaults.integer(forKey: "expiryMinutes"))
            ? defaults.integer(forKey: "expiryMinutes") : 30
        maxItems =
            [5, 10, 20, 50].contains(defaults.integer(forKey: "maxItems")) ? defaults.integer(forKey: "maxItems") : 20
        side = StackSide(rawValue: defaults.string(forKey: "stackSide") ?? "right") ?? .right
        doubleOptionEnabled = defaults.bool(forKey: "doubleOptionEnabled")
        shortcutKeyCode = UInt32(clamping: defaults.integer(forKey: "shortcutKeyCode"))
        shortcutModifiers = UInt32(clamping: defaults.integer(forKey: "shortcutModifiers"))
        agentAccessEnabled = defaults.bool(forKey: "agentAccessEnabled")
        agentScreenCaptureEnabled = defaults.bool(forKey: "agentScreenCaptureEnabled")
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }

    public var shortcutLabel: String {
        var label = ""
        if shortcutModifiers & UInt32(controlKey) != 0 { label += "⌃" }
        if shortcutModifiers & UInt32(optionKey) != 0 { label += "⌥" }
        if shortcutModifiers & UInt32(shiftKey) != 0 { label += "⇧" }
        if shortcutModifiers & UInt32(cmdKey) != 0 { label += "⌘" }
        return label + Self.keyLabel(shortcutKeyCode)
    }

    public static let keys: [(code: UInt32, label: String)] = [
        (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"), (34, "I"),
        (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"), (35, "P"), (12, "Q"),
        (15, "R"), (1, "S"), (17, "T"), (32, "U"), (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"), (28, "8"), (25, "9"), (29, "0"),
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
        (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12"),
    ]
    public static func keyLabel(_ code: UInt32) -> String {
        keys.first { $0.code == code }?.label ?? L10n.format("Key %u", code)
    }
}
