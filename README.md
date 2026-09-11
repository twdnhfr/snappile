# SnapPile

Ein temporärer visueller Zwischenspeicher für KI-Workflows. Nativ für macOS: Bereich aufnehmen, kurz im schwebenden Stapel sammeln und direkt weitergeben.

## Starten

Die lokal gebaute App liegt in `outputs/SnapPile.app`. Öffne sie per Doppelklick. SnapPile sitzt in der Menüleiste und hat kein Dock-Symbol. Beim ersten Start führt ein eigener Onboarding-Bildschirm durch die macOS-Freigaben. Die erste Aufnahme ist erst nach bestätigtem Bildschirmzugriff möglich. Die Einrichtung ist später über das Menü erneut erreichbar.

1. Über **Bildschirm freigeben …** im Onboarding oder **Bildschirmaufnahme → Erlauben …** in den Einstellungen die macOS-Freigabe für SnapPile aktivieren. Falls macOS einen Neustart der App verlangt, SnapPile beenden und erneut öffnen.
2. Optional **Eingabeüberwachung → Erlauben …** aktivieren, damit linke und rechte Option-Taste zusammen die Aufnahme auslösen können. Das Ersatz-Kürzel benötigt diese Freigabe nicht. Der Option-Hotkey wertet die links-/rechtsspezifischen Modifier-Flags des jeweiligen Ereignisses aus.
3. **⌃⌥S** drücken oder im Menü **Bereich aufnehmen** wählen. Einen Bereich ziehen; **Esc** bricht ab.
4. Das Bild erscheint am Bildschirmrand. Auf die Karte klicken öffnet die Vorschau; Ziehen übergibt das Original an ein kompatibles Ziel.

## MVP-Funktionen

- Bereichsauswahl auf einem beliebigen angeschlossenen Bildschirm; eine Aufnahme bleibt auf den Bildschirm beschränkt, auf dem die Auswahl begonnen wurde.
- Floating Panel ohne Fokuswechsel, mit bis zu drei versetzten Karten und Zähler für weitere Bilder; aufklappbare Liste für den gesamten Stapel.
- Original-PNG kopieren, als PNG speichern, löschen oder anheften.
- Drag-and-drop als Bild und als macOS-Dateiversprechen. Eine Datei wird dabei erst beim angenommenen Drop am vom Empfänger bestimmten Ziel geschrieben.
- Konfigurierbares Ersatz-Kürzel: Buchstaben, Ziffern und F-Tasten mit Command, Control, Option und/oder Shift. Konflikte werden angezeigt; das bisherige Kürzel bleibt bei einem fehlgeschlagenen Wechsel aktiv.
- Aufbewahrung: 5, 15, 30, 60 oder 120 Minuten; Standard 30 Minuten. Ablaufprüfung alle fünf Sekunden und nach dem Aufwachen.
- Limit: 5, 10, 20 oder 50 Bilder; Standard 20. Zusätzlich höchstens 256 MiB komprimierte PNG-Daten im Stapel.
- Position links oder rechts; neue Aufnahmen platzieren den Stapel auf dem verwendeten Bildschirm.

## Lebensdauer der Bilder

SnapPile speichert Aufnahmen nicht automatisch in Dateien, einer Datenbank oder der Cloud. Vollbilder liegen komprimiert als PNG im Speicher; Vorschaubilder sind auf 520 Pixel Kantenlänge begrenzt. Nur Einstellungen werden dauerhaft in den macOS-Benutzereinstellungen gespeichert.

Bei Platzmangel verschwinden zuerst die ältesten ungepinnten Bilder. Pins verhindern Ablauf und automatisches Verwerfen. Belegen Pins den gesamten Platz, wird eine neue Aufnahme mit einer Meldung abgelehnt. Beim manuellen Löschen oder Beenden der App verschwinden auch Pins. Nach Lösen eines Pins gilt weiterhin das ursprüngliche Aufnahmealter.

Das 256-MiB-Limit bezieht sich auf PNG-Daten, nicht auf den gesamten Prozessspeicher: Thumbnails, Aufnahme und geöffnete Vollbildvorschau benötigen zusätzlich Speicher. macOS kann Arbeitsspeicher auslagern. Kopierte, gespeicherte oder an andere Apps übergebene Bilder unterliegen deren eigener Aufbewahrung; SnapPile kann sie dort nicht zurückholen.

## Entwickeln

Voraussetzung: macOS 14 oder neuer und eine passende Xcode-/Swift-Toolchain. Keine Drittanbieter-Abhängigkeiten.

```sh
swift test
bash scripts/build-app.sh
open outputs/SnapPile.app
```

Der Build erzeugt eine App für die Architektur des ausführenden Macs und signiert sie standardmäßig lokal ad hoc. Mit `SNAPPILE_SIGNING_IDENTITY` lässt sich eine vorhandene Codesigning-Identität verwenden. Die ausgelieferte lokale Version ist mit der vorhandenen Developer-ID signiert; eine Notarisierung wurde nicht durchgeführt. Der geprüfte Build liegt zusätzlich in `outputs/SnapPile-macOS.zip`.

Für Oberflächentests lässt sich ein leer gestarteter Prozess mit vier synthetischen Beispielbildern öffnen:

```sh
open outputs/SnapPile.app --args --demo
```

Demo-Bilder sind ausdrücklich als Beispiel gekennzeichnet. Dieser Modus ist ausschließlich für Tests; normal startet der Stapel leer. Vor einem erneuten Demo-Start eine bereits laufende Instanz über das Menü beenden.

## Aufbau

- `Sources/SnapPile`: AppKit-Lebenszyklus, SwiftUI-Oberflächen, Menüleiste und Panels.
- `Sources/SnapPileCore`: Aufnahme, Auswahl, Hotkeys, Speicher, Einstellungen und Bildübergabe.
- `Tests/SnapPileCoreTests`: synthetische Regressionstests ohne echte Bildschirmdaten.
- `Support/Info.plist`: App-Bundle und Berechtigungstexte.
- `scripts/build-app.sh`: reproduzierbarer lokaler App-Build.

Der Projektaufbau orientiert sich am schlanken SwiftPM-/AppKit-Muster von MenuTune und DevWatch. Deren vorhandene Projekte wurden nicht verändert.

## Grenzen von Version 0.1

Keine Bildbearbeitung, Cloud, Anmeldung, Datenbank oder Mehrfachauswahl. Bildschirmübergreifende Auswahl und ein gemeinsamer Drag mehrerer Bilder sind noch nicht enthalten. Die Annahme von Drag-and-drop hängt vom Zielprogramm ab; Kopieren und PNG-Speichern bleiben weitere Übergabewege. Ein veröffentlichungsfertiger, notarialisierter Universal-Build ist nicht Bestandteil dieses lokalen MVP.
