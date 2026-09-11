import Foundation

/// Localized user-facing strings used by the core module.
public enum L10n {
    public static func text(_ key: String) -> String {
        resourceBundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    internal static var resourceBundleForTesting: Bundle? { resourceBundle }

    /// The app embeds the core resource bundle below its Resources directory.
    /// SwiftPM uses Bundle.module for command-line and test builds. In a
    /// packaged app, a missing embedded bundle must remain an English fallback
    /// instead of touching the generated Bundle.module accessor.
    private static var resourceBundle: Bundle? {
        if let url = Bundle.main.url(forResource: "SnapPile_SnapPileCore", withExtension: "bundle"),
            let bundle = Bundle(url: url)
        {
            return bundle
        }
        guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
        return Bundle.module
    }
}
