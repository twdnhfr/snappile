# SnapPile · Branding

Drei versetzte Screenshot-Karten und zwei gegenüberliegende Aufnahme-Ecken bilden die Bildmarke. Das macOS-App-Icon ergänzt die Karten um eine Graphit-Kachel mit dezenter Tiefe. Die Menüleiste verwendet eine vereinfachte, einfarbige Kontur.

## Dateien

- `AppIcon.png`: hochauflösender RGBA-Master mit transparentem Außenraum. Der App-Build erzeugt daraus alle zehn Standardgrößen für `AppIcon.icns`.
- `snappile-logo-light.svg`: transparentes Logo mit dunkler Schrift für helle Hintergründe.
- `snappile-logo-dark.svg`: transparentes Logo mit heller Schrift für dunkle Hintergründe.
- [`BrandMark.svg`](../../Sources/SnapPile/Resources/BrandMark.svg): editierbare, farbige Bildmarke für die App und die Logos.
- [`MenuBarMark.svg`](../../Sources/SnapPile/Resources/MenuBarMark.svg): separate, monochrome Kontur für die Menüleiste; macOS übernimmt deren Einfärbung.
- [`BrandIcon.png`](../../Sources/SnapPile/Resources/BrandIcon.png): 256-Pixel-Ableitung des Masters für Onboarding und Einstellungen.

Die README wählt die Logo-Variante über `prefers-color-scheme`. Alle Buchstaben sind als Pfade eingebettet; Betrachter benötigen keine Schriftinstallation. Die Marken-Assets stehen wie das Projekt unter der [MIT-Lizenz](../../LICENSE).

## Farben

| Einsatz | Farbe |
| --- | --- |
| Mint, vordere Karte | `#63E6BE` |
| Jade, mittlere Karte | `#23AB90` |
| Petrol, hintere Karte | `#147C70` |
| Aufnahme-Ecken | `#183B39` |
| Wortmarke auf Hell | `#193A37` |
| Wortmarke auf Dunkel | `#F0F8F5` |

## Aktualisieren

Nach einer Änderung an `BrandMark.svg` lassen sich die Wortmarken auf macOS neu erzeugen:

```sh
swift scripts/make-brand.swift
```

Nach einem neuen Icon-Master auch die kleine App-Ressource erneuern:

```sh
sips -z 256 256 Support/Brand/AppIcon.png --out Sources/SnapPile/Resources/BrandIcon.png
bash scripts/build-app.sh
```

Die Bildmarke und Wortmarken sind native SVG-Assets. Der Icon-Master entstand mit dem integrierten Bildgenerator (`imagegen`, keine externe CLI). Der verwendete Prompt ist unter [icon-prompt.txt](icon-prompt.txt) dokumentiert.
