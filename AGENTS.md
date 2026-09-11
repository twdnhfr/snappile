# SnapPile

- Antworte auf Deutsch, sofern nicht anders gewünscht.
- Native macOS-App: Swift, SwiftUI, AppKit, ScreenCaptureKit. Keine Web-Wrapper oder externen Laufzeitabhängigkeiten.
- Aufnahmen nur im Arbeitsspeicher halten. Auf Platte schreiben ausschließlich bei ausdrücklichem Speichern oder beim angenommenen Dateiversprechen eines Drop-Empfängers.
- Vollbilder komprimiert halten; UI darf nur begrenzte Thumbnails dauerhaft dekodiert halten.
- Pins vor automatischem Verwerfen schützen, beim Beenden alles freigeben.
- Tests mit synthetischen Bildern; keine privaten Screenshots in Fixtures oder Logs.
- Build: `bash scripts/build-app.sh`; Tests: `swift test`.
- Freigaben in macOS sind Benutzereinstellungen; nicht durch Datenbankmanipulationen umgehen.
