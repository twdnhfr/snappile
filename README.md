# SnapPile

Ein temporärer visueller Zwischenspeicher für KI-Workflows. Nativ für macOS: Bereich aufnehmen, kurz im schwebenden Stapel sammeln und direkt weitergeben.

## Starten

Die lokal gebaute App liegt in `outputs/SnapPile.app`. Öffne sie per Doppelklick. SnapPile sitzt in der Menüleiste und hat kein Dock-Symbol. Beim ersten Start führt ein eigener Onboarding-Bildschirm durch die macOS-Freigaben. Die erste Aufnahme ist erst nach bestätigtem Bildschirmzugriff möglich. Die Einrichtung ist später über das Menü erneut erreichbar.

1. Über **Bildschirm freigeben …** im Onboarding oder **Bildschirmaufnahme → Erlauben …** in den Einstellungen die macOS-Freigabe für SnapPile aktivieren. Falls macOS einen Neustart der App verlangt, SnapPile beenden und erneut öffnen.
2. Optional **Eingabeüberwachung → Erlauben …** aktivieren, damit linke und rechte Option-Taste zusammen die Aufnahme auslösen können. Das Ersatz-Kürzel benötigt diese Freigabe nicht. Der Option-Hotkey wertet die links-/rechtsspezifischen Modifier-Flags des jeweiligen Ereignisses aus.
3. **⌃⌥S** drücken oder im Menü **Bereich aufnehmen** wählen. Einen Bereich ziehen; währenddessen **Leertaste halten**, um die ganze Box zu verschieben. Nach Loslassen der Leertaste wieder die Größe anpassen. **Esc** bricht ab.
4. Das Bild erscheint am Bildschirmrand. Auf die Karte klicken öffnet die Vorschau; Ziehen übergibt das Original an ein kompatibles Ziel.

## MVP-Funktionen

- Bereichsauswahl auf einem beliebigen angeschlossenen Bildschirm; eine Aufnahme bleibt auf den Bildschirm beschränkt, auf dem die Auswahl begonnen wurde.
- Floating Panel ohne Fokuswechsel, mit bis zu drei versetzten Karten und Zähler für weitere Bilder. Klick auf den Zähler öffnet oder schließt die Liste des gesamten Stapels. Jede Vorschau ist 175 × 175 Punkte groß und zeigt einen zentrierten, quadratischen Ausschnitt ohne Füllflächen. Das vollständige Original bleibt beim Öffnen, Kopieren, Speichern und Ziehen erhalten. Overlay-Icons dienen zum Kopieren, Speichern, Anheften und Löschen.
- Original-PNG kopieren, als PNG speichern, löschen oder anheften.
- Im eingeklappten Stapel per Trackpad oder Mausrad vor- und zurückblättern, horizontal oder vertikal. Der Zähler zeigt die aktuelle Position. Nach dem letzten Bild folgt wieder das erste. Eine Trackpad-Geste wechselt höchstens ein Bild; ihre Trägheit wird ignoriert. In der aufgeklappten Liste wird normal gescrollt. Neue Aufnahmen erscheinen vorne, das Blättern ändert die Reihenfolge und Lebensdauer der Bilder nicht.
- Drag-and-drop mit einer vorhandenen temporären PNG-Datei und den Original-PNG-Daten als alternative Darstellung desselben Drag-Items. Dadurch können auch Ziele mit klassischem Dateidrop das Bild übernehmen.
- Konfigurierbares Ersatz-Kürzel: Buchstaben, Ziffern und F-Tasten mit Command, Control, Option und/oder Shift. Konflikte werden angezeigt; das bisherige Kürzel bleibt bei einem fehlgeschlagenen Wechsel aktiv.
- Aufbewahrung: 5, 15, 30, 60 oder 120 Minuten; Standard 30 Minuten. Ablaufprüfung alle fünf Sekunden und nach dem Aufwachen.
- Limit: 5, 10, 20 oder 50 Bilder; Standard 20. Zusätzlich höchstens 256 MiB komprimierte PNG-Daten im Stapel.
- Position links oder rechts; neue Aufnahmen platzieren den Stapel auf dem verwendeten Bildschirm.

## Lebensdauer der Bilder

Aufnahmen liegen zunächst ausschließlich als komprimierte PNG-Daten im Speicher; Vorschaubilder sind auf 520 Pixel Kantenlänge begrenzt. Es gibt keine Datenbank und keine Cloud. Einstellungen werden dauerhaft in den macOS-Benutzereinstellungen gespeichert.

Erst beim Ziehen erstellt SnapPile eine PNG im benutzereigenen Temp-Verzeichnis `de.wdnhfr.snappile-drag`. Die Verzeichnisse sind nur für den aktuellen Benutzer zugänglich. Wiederholtes Ziehen derselben Aufnahme verwendet dieselbe Datei. Nach Ende eines Drags bleibt sie noch 30 Minuten verfügbar, damit Empfänger sie verzögert einlesen können; die Bereinigung läuft alle fünf Sekunden. Aktive Drags sind davon ausgenommen. Beim Beenden werden alle eigenen Exportdateien gelöscht. Nach einem Absturz räumt der nächste Start verwaiste Sitzungsverzeichnisse auf. Pins schützen die Aufnahme im Stapel, verlängern aber nicht die Lebensdauer einer Exportdatei.

Der temporäre Export ist auf 50 Dateien und 256 MiB begrenzt. Ist der Platz noch durch laufende oder kürzlich beendete Übergaben belegt, wird ein neuer Drag mit einer Meldung abgelehnt. Kopieren und explizites Speichern bleiben möglich. Eine Exportdatei wird nicht schon beim Loslassen oder beim Löschen ihrer Karte entfernt, weil das Ziel sie noch lesen kann.

Bei Platzmangel verschwinden zuerst die ältesten ungepinnten Bilder. Pins verhindern Ablauf und automatisches Verwerfen. Belegen Pins den gesamten Platz, wird eine neue Aufnahme mit einer Meldung abgelehnt. Beim manuellen Löschen oder Beenden der App verschwinden auch Pins. Nach Lösen eines Pins gilt weiterhin das ursprüngliche Aufnahmealter.

Das 256-MiB-Limit bezieht sich auf PNG-Daten, nicht auf den gesamten Prozessspeicher: Thumbnails, Aufnahme und geöffnete Vollbildvorschau benötigen zusätzlich Speicher. macOS kann Arbeitsspeicher auslagern. Kopierte, gespeicherte oder an andere Apps übergebene Bilder unterliegen deren eigener Aufbewahrung; SnapPile kann sie dort nicht zurückholen.

## Entwickeln

Voraussetzung: macOS 14 oder neuer und eine passende Xcode-/Swift-Toolchain. Keine Drittanbieter-Abhängigkeiten.

```sh
swift test
bash scripts/build-app.sh
open outputs/SnapPile.app
```

Der lokale Build erzeugt eine App für die Architektur des ausführenden Macs. Ohne gesetztes `SNAPPILE_SIGNING_IDENTITY` wird genau eine gültige Identität vom Typ `Developer ID Application:` automatisch verwendet. Gibt es mehrere passende Identitäten, bricht der Build mit einer Aufforderung zur expliziten Auswahl ab. Gibt es keine, wird mit einer Warnung ad hoc signiert. Mit `SNAPPILE_SIGNING_IDENTITY` lässt sich die Identität explizit setzen; `SNAPPILE_SIGNING_IDENTITY=-` erzwingt bewusst eine ad-hoc-Signatur. Dieser lokale Build ist nicht notarisiert. Das geprüfte Archiv liegt zusätzlich in `outputs/SnapPile-macOS.zip`.

### Signierter und notarisierter Production-Build

```sh
NOTARY_PROFILE=mein-schluesselbundprofil bash scripts/build-app.sh production
```

Voraussetzungen sind eine gültige Developer-ID-Application-Identität und ein bereits eingerichtetes `notarytool`-Schlüsselbundprofil für das zugehörige Apple-Developer-Team. Zugangsdaten gehören ausschließlich in den Schlüsselbund; `NOTARY_PROFILE` enthält nur dessen Profilnamen. Der Production-Modus akzeptiert keine ad-hoc-Signatur.

Der Build erstellt eine Universal-App für Apple Silicon und Intel, signiert mit Hardened Runtime und sicherem Zeitstempel und übermittelt App sowie DMG an Apples Notarisierungsdienst. Nach erfolgreicher Prüfung werden die Tickets angeheftet. Signatur, Ticket und Gatekeeper-Freigabe werden auch für die exportierte App und ein erneut entpacktes ZIP geprüft. Dieser Ablauf folgt [Apples Notarisierungsverfahren](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Die fertigen Dateien liegen getrennt von lokalen Builds in `outputs/production/`: `SnapPile.app`, `SnapPile-macOS.zip`, `SnapPile-<Version>.dmg` und die beiden Notarisierungsberichte. Das DMG enthält eine Verknüpfung zu Programme zum Installieren per Ziehen. Der Build installiert oder veröffentlicht nichts automatisch. Eine laufende SnapPile-Instanz vor dem Austausch beenden; dabei wird ihr temporärer Stapel verworfen.

Wenn eine eingeschaltete Eingabeüberwachungs- oder Bildschirmaufnahme-Freigabe nach einem Signaturwechsel veraltet ist, SnapPile in den macOS-Einstellungen aus beiden Freigabelisten entfernen, `/Applications/SnapPile.app` erneut hinzufügen und SnapPile neu starten.

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
- `scripts/build-app.sh`: lokaler App-Build sowie signierter und notarisierter Production-Build.

Der Projektaufbau orientiert sich am schlanken SwiftPM-/AppKit-Muster von MenuTune und DevWatch. Deren vorhandene Projekte wurden nicht verändert.

## Grenzen von Version 0.1

Weitere vorgemerkte Funktionen stehen in [BACKLOG.md](BACKLOG.md).

Keine Bildbearbeitung, Cloud, Anmeldung, Datenbank oder Mehrfachauswahl. Bildschirmübergreifende Auswahl und ein gemeinsamer Drag mehrerer Bilder sind noch nicht enthalten. Die Annahme von Drag-and-drop hängt vom Zielprogramm ab; Kopieren und PNG-Speichern bleiben weitere Übergabewege. Ein erfolgreicher Production-Build bestätigt Signatur und Notarisierung; er ersetzt keinen Funktionstest auf einem Intel-Mac oder in jedem Drag-Empfänger.
