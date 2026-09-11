# SnapPile · Branding

Three offset screenshot cards and two opposing capture corners form the brand mark. The macOS app icon adds a graphite tile with subtle depth. The menu bar uses a simplified monochrome outline.

## Files

- `AppIcon.png`: high-resolution RGBA master with transparent outer space. The app build derives all ten standard iconset sizes for `AppIcon.icns`.
- `snappile-logo-light.svg`: transparent logo with dark lettering for light backgrounds.
- `snappile-logo-dark.svg`: transparent logo with light lettering for dark backgrounds.
- [`BrandMark.svg`](../../Sources/SnapPile/Resources/BrandMark.svg): editable color mark shared by the app and wordmarks.
- [`MenuBarMark.svg`](../../Sources/SnapPile/Resources/MenuBarMark.svg): separate monochrome outline for the menu bar; macOS supplies its tint.
- [`BrandIcon.png`](../../Sources/SnapPile/Resources/BrandIcon.png): 256-pixel derivative of the master for onboarding and settings.

The README selects a logo using `prefers-color-scheme`. All letters are embedded as paths, so viewers do not need the font installed. Like the project, these assets are available under the [MIT license](../../LICENSE).

## Colors

| Use | Color |
| --- | --- |
| Mint, front card | `#63E6BE` |
| Jade, middle card | `#23AB90` |
| Teal, back card | `#147C70` |
| Capture corners | `#183B39` |
| Lettering on light backgrounds | `#193A37` |
| Lettering on dark backgrounds | `#F0F8F5` |

## Updating the assets

After editing `BrandMark.svg`, regenerate the wordmarks on macOS:

```sh
swift scripts/make-brand.swift
```

After replacing the icon master, update the smaller app resource as well:

```sh
sips -z 256 256 Support/Brand/AppIcon.png --out Sources/SnapPile/Resources/BrandIcon.png
bash scripts/build-app.sh
```

The mark and wordmarks are native SVG assets. The icon master was created with the built-in image generator (`imagegen`, not an external CLI). The full prompt is documented in [icon-prompt.txt](icon-prompt.txt).
