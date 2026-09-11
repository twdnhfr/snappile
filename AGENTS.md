# SnapPile

- Antworte auf Deutsch, sofern nicht anders gewünscht.
- Native macOS-App: Swift, SwiftUI, AppKit, ScreenCaptureKit. Keine Web-Wrapper oder externen Laufzeitabhängigkeiten.
- Aufnahmen standardmäßig im Arbeitsspeicher halten. Beim Start eines Drag-and-drop darf eine temporäre PNG-Datei für dateibasierte Empfänger entstehen; nur in einem privaten Temp-Verzeichnis, mit begrenzter Lebensdauer und Bereinigung beim Beenden. Dauerhafte Dateien ausschließlich bei ausdrücklichem Speichern oder durch den Drop-Empfänger.
- Vollbilder komprimiert halten; UI darf nur begrenzte Thumbnails dauerhaft dekodiert halten.
- Pins vor automatischem Verwerfen schützen, beim Beenden alles freigeben.
- Tests mit synthetischen Bildern; keine privaten Screenshots in Fixtures oder Logs.
- Build: `bash scripts/build-app.sh`; Tests: `swift test`.
- Freigaben in macOS sind Benutzereinstellungen; nicht durch Datenbankmanipulationen umgehen.
