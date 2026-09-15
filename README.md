<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Support/Brand/snappile-logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="Support/Brand/snappile-logo-light.svg">
    <img src="Support/Brand/snappile-logo-light.svg" alt="SnapPile" width="360">
  </picture>
</h1>

A temporary visual clipboard for AI workflows. Native to macOS: capture an area, collect it in a floating stack, and drag it where you need it.

## Install and get started

Download the notarized DMG from [Releases](https://github.com/twdnhfr/snappile/releases) and drag SnapPile into Applications. You can also [build it yourself](#development). SnapPile lives in the menu bar and does not show a Dock icon. On first launch, onboarding guides you through macOS permissions. Screen access must be granted before the first capture. You can reopen setup from the menu at any time.

1. Use **Allow Screen Access…** in onboarding or **Screen Recording → Allow…** in Settings to grant screen access. If macOS asks you to restart SnapPile, quit and reopen it.
2. Optionally enable **Input Monitoring → Allow…** to capture by pressing the left and right Option keys together. The fallback shortcut does not need this permission. The double-Option shortcut tracks each key using the event's left/right modifier flags.
3. Press **⌃⌥S** or choose **Capture Area** from the menu. Drag to select an area; **hold Space** to move the entire selection. Release Space to resize it again. **Return** confirms the current selection; **Esc** cancels.
4. The screenshot appears at the edge of your screen. Click the card to preview it, or drag it into a compatible app to transfer the original image.

## Features

- Select an area on any connected display. A capture stays on the display where the selection began.
- A floating panel that does not steal focus, with up to three offset cards and a counter. Click the counter to expand or collapse the full stack. Each preview is a centered **175 × 175-point square crop**, without padding. Opening, copying, saving, and dragging always use the complete original. Small overlay icons provide Copy, Save, Pin, and Delete.
- Copy the original PNG, save it as a PNG file, pin it, or delete it.
- Browse the collapsed stack with a trackpad or mouse wheel, horizontally or vertically. The counter shows the current position, and browsing wraps after the last image. Each trackpad gesture moves by at most one image; momentum is ignored. The expanded list scrolls normally. New captures appear first; browsing does not change their order or lifetime.
- Drag and drop using an existing temporary PNG file, with the original PNG data as an alternative representation of the same item. This also supports apps that expect a traditional file drop.
- Configure the fallback shortcut using letters, numbers, or function keys with Command, Control, Option, and/or Shift. Shortcuts already taken by enabled macOS system shortcuts or rejected by macOS are reported, and the previous shortcut stays active if a change fails.
- Retention: 5, 15, 30, 60, or 120 minutes; 30 minutes by default. Expiry is checked every five seconds and after wake.
- Stack limit: 5, 10, 20, or 50 images; 20 by default. Compressed PNG data in the stack is also limited to 256 MiB.
- Choose the left or right edge. New captures place the stack on the display used for the capture.

## Image lifetime

Captures initially exist only as compressed PNG data in memory. Thumbnails are limited to a maximum edge length of 520 pixels. There is no database or cloud service. Preferences are stored in macOS user defaults.

Starting a drag creates a PNG in a private subdirectory of the user's temporary directory, named after the bundle identifier with a `-drag` suffix. Only the current user can access these directories. Export files are read-only. Dragging the same capture again reuses its file, or writes it again from the original if a receiver replaced or removed it. After a drag ends, the file remains available for 30 minutes so receivers can read it asynchronously; cleanup runs every five seconds. Active drags are exempt from cleanup. The PNG data that macOS keeps on the drag pasteboard is cleared together with the export file, unless a later drag has replaced it. Quitting removes all export files owned by that session. After a crash, the next launch cleans up abandoned session directories. Pins protect images in the stack but do not extend an export file's lifetime.

Temporary exports are limited to 50 files and 256 MiB. If active or recent transfers still occupy that space, a new drag is declined with an explanation. Copying and explicit saving remain available. An export file is not deleted immediately after dropping or deleting its card, because the receiving app may still need to read it.

When the stack is full, the oldest unpinned images are removed first. Pins prevent expiry and automatic removal. If pinned images occupy all available space, a new capture is declined with an explanation. Manual deletion and quitting also discard pinned images. Unpinning restores the original capture-based expiry time.

The 256 MiB limit applies to PNG data, not total process memory: thumbnails, capture operations, and open full-size previews need additional memory. macOS may swap memory to disk. Images copied, saved, or transferred to another app follow that destination's retention rules; SnapPile cannot remove those copies.

## Language and localization

Starting with version 0.1.4, English is the app's base and fallback language. This includes menus, onboarding, settings, accessibility labels, capture hints, and errors. macOS selects from the translations shipped with an app; it does not automatically translate its interface. SnapPile currently includes English only, so it also falls back to English when the preferred system language is different.

App and core strings use `L10n.text` and `L10n.format`, backed by `Sources/SnapPileCore/Resources/en.lproj/Localizable.strings` and, for count-dependent plural forms, `Localizable.stringsdict`. A test checks that the keys used in the sources and the catalog match. Complete sentences use format placeholders rather than string fragments, allowing translations to reorder their arguments. Permission descriptions live in `Support/en.lproj/InfoPlist.strings`.

To add a language, provide a matching `.lproj/Localizable.strings` and `.lproj/Localizable.stringsdict` under the core resources and an `.lproj/InfoPlist.strings` under `Support`, then add its language code to `CFBundleLocalizations` in `Support/Info.plist`. Keep localization keys and format placeholder types intact. The build packages both resource bundles and the permission strings; it does not require the source checkout at runtime. Keep `defaultLocalization` and `CFBundleDevelopmentRegion` set to `en` for fallback.

## Development

Requires macOS 14 or later and Swift 5.10 or later (Xcode 15.3). No third-party dependencies.

```sh
swift test
bash scripts/build-app.sh
open outputs/SnapPile.app
```

Render tests write comparison images to `$TMPDIR/SnapPileTests`, outside the repository. Test images are synthetic.

Formatting is configured in `.swift-format`. Before committing, run `swift format --in-place --recursive Sources Tests Package.swift scripts/*.swift`. The workflow in `.github/workflows/ci.yml` checks formatting, builds the project, runs tests, and builds an ad hoc signed app bundle on every push to `main` and on pull requests.

A local build targets the current Mac's architecture. If `SNAPPILE_SIGNING_IDENTITY` is unset, the script automatically uses a single valid `Developer ID Application:` identity. Multiple matching identities require an explicit selection. If none is available, the script warns and uses ad hoc signing. Set `SNAPPILE_SIGNING_IDENTITY` to choose an identity; set `SNAPPILE_SIGNING_IDENTITY=-` to explicitly request ad hoc signing. Local builds are not notarized. A verified archive is also written to `outputs/SnapPile-macOS.zip`.

### Signed and notarized production build

```sh
NOTARY_PROFILE=my-keychain-profile bash scripts/build-app.sh production
```

Requires a valid Developer ID Application identity and an existing `notarytool` keychain profile for the corresponding Apple Developer team. Credentials belong in the keychain; `NOTARY_PROFILE` contains only the profile name. Production builds reject ad hoc signing.

The script builds a universal app for Apple Silicon and Intel, signs it with Hardened Runtime and a secure timestamp, and submits both the app and DMG to Apple's notarization service. Accepted tickets are stapled to the artifacts. It checks the signature, ticket, and Gatekeeper acceptance for the exported app and an extracted copy of the ZIP, following [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Production artifacts are separate from local builds in `outputs/production/`: `SnapPile.app`, `SnapPile-macOS.zip`, `SnapPile-<version>.dmg`, and the two notarization reports. The DMG includes an Applications shortcut for drag-to-install. The script does not install or publish automatically. Quit a running SnapPile instance before replacing it; quitting discards its temporary stack.

If Screen Recording or Input Monitoring remains enabled in macOS but stops working after a signing identity change, remove SnapPile from both permission lists, add `/Applications/SnapPile.app` again, and restart it.

To launch with four synthetic images for UI testing:

```sh
open outputs/SnapPile.app --args --demo
```

Demo images are explicitly labeled as examples. This mode is for testing only; a normal launch starts with an empty stack. Quit any existing instance from its menu before launching demo mode again.

## Project structure

- `Sources/SnapPile`: AppKit lifecycle, SwiftUI views, menu bar, and panels.
- `Sources/SnapPileCore`: capture, selection, shortcuts, storage, preferences, image transfer, and localization.
- `Sources/SnapPileCore/Resources`: localized interface strings, with English as the base language.
- `Tests/SnapPileCoreTests`: regression tests using synthetic data.
- `Tests/SnapPileAppTests`: synthetic stack and menu layout/navigation tests.
- `Support/Info.plist` and `Support/*.lproj`: app metadata and localized permission descriptions.
- `Sources/SnapPile/Resources`: interface icon, color brand mark, and monochrome menu bar mark.
- `Support/Brand`: icon master and scalable light/dark logos; see [Branding](Support/Brand/README.md).
- `scripts/build-app.sh`: local and signed/notarized production builds. `scripts/make-icon.swift` creates an iconset from the PNG master; `scripts/make-brand.swift` generates the README logos with embedded letter outlines.

## Version 0.1 limitations

Tracked features are listed in [BACKLOG.md](BACKLOG.md).

No image editing, cloud service, accounts, database, or multiple selection. Selection across displays and dragging multiple images together are not supported yet. Drag acceptance depends on the receiving app; copying and saving a PNG provide alternative transfer options. A successful production build verifies signing and notarization, not functionality on an Intel Mac or in every possible drop target.

## License

MIT. See [LICENSE](LICENSE).
