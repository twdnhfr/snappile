# SnapPile

- Respond in German unless the user asks for another language.
- Native macOS app: Swift, SwiftUI, AppKit, and ScreenCaptureKit. No web wrappers or external runtime dependencies.
- Keep captures in memory by default. Starting a drag may create a temporary PNG for file-based receivers, in a private temporary directory with a bounded lifetime and cleanup on quit. Create permanent files only when the user explicitly saves or the drop receiver does so.
- Keep full images compressed; the UI may retain only bounded decoded thumbnails.
- Protect pinned captures from automatic removal; release everything when the app quits.
- Use synthetic images in tests; never put private screenshots in fixtures or logs.
- English is the app's base and fallback language. Route user-facing strings through `L10n` and maintain the English catalog. Keep localization keys, internal identifiers, and behavior separate.
- Build: `bash scripts/build-app.sh`; tests: `swift test`.
- macOS permissions are user settings; never bypass them by manipulating databases.
