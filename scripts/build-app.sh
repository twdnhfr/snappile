#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' Support/Info.plist)"
MODE="${1:-release}"
if [[ "$MODE" != "release" && "$MODE" != "debug" && "$MODE" != "production" ]]; then
  echo "Usage: scripts/build-app.sh [release|debug|production]" >&2
  exit 1
fi
CONFIGURATION="$MODE"
if [[ "$MODE" == "production" ]]; then
  CONFIGURATION="release"
  if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    echo "Production requires NOTARY_PROFILE naming an existing notarytool keychain profile." >&2
    exit 1
  fi
fi

if [[ ${SNAPPILE_SIGNING_IDENTITY+x} == x ]]; then
  SIGNING_IDENTITY="$SNAPPILE_SIGNING_IDENTITY"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "SNAPPILE_SIGNING_IDENTITY is set but empty. Provide an identity or '-' for ad hoc signing." >&2
    exit 1
  fi
else
  IDENTITY_OUTPUT="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  IDENTITIES=()
  IDENTITY_LABELS=()
  while IFS= read -r line; do
    if [[ "$line" == *'"Developer ID Application:'* ]]; then
      candidate="${line#*) }"
      candidate_hash="${candidate%% *}"
      candidate_label="${candidate#*\"}"
      candidate_label="${candidate_label%%\"*}"
      if [[ "$candidate_hash" =~ ^[[:xdigit:]]{40}$ ]]; then
        IDENTITIES+=("$candidate_hash")
        IDENTITY_LABELS+=("$candidate_label")
      fi
    fi
  done <<< "$IDENTITY_OUTPUT"

  if [[ ${#IDENTITIES[@]} -eq 1 ]]; then
    SIGNING_IDENTITY="${IDENTITIES[0]}"
    echo "Using the automatically detected signing identity: ${IDENTITY_LABELS[0]}"
  elif [[ ${#IDENTITIES[@]} -gt 1 ]]; then
    echo "Multiple valid Developer ID Application identities found. Set SNAPPILE_SIGNING_IDENTITY explicitly:" >&2
    printf '  %s\n' "${IDENTITY_LABELS[@]}" >&2
    exit 1
  else
    SIGNING_IDENTITY="-"
    echo "Warning: No valid Developer ID Application identity found; using ad hoc signing. macOS permissions may become invalid after each build." >&2
  fi
fi

if [[ "$MODE" == "production" && "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Production requires a Developer ID Application signature; ad hoc signing is not allowed." >&2
  exit 1
fi
BUILD_ARGUMENTS=(-c "$CONFIGURATION")
if [[ "$MODE" == "production" ]]; then
  BUILD_ARGUMENTS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGUMENTS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"
# Sign outside synced Documents folders: File Provider may otherwise attach
# FinderInfo between xattr cleanup and codesign, invalidating the app bundle.
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/snappile-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_DIR="$STAGING_DIR/SnapPile.app"
OUTPUT_DIR="$PROJECT_DIR/outputs"
if [[ "$MODE" == "production" ]]; then
  OUTPUT_DIR="$OUTPUT_DIR/production"
fi
OUTPUT_APP="$OUTPUT_DIR/SnapPile.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$PROJECT_DIR/work" "$OUTPUT_DIR"
cp "$BIN_DIR/SnapPile" "$APP_DIR/Contents/MacOS/SnapPile"
cp Support/Info.plist "$APP_DIR/Contents/Info.plist"
for RESOURCE_NAME in SnapPile_SnapPile SnapPile_SnapPileCore; do
  RESOURCE_BUNDLE="$BIN_DIR/$RESOURCE_NAME.bundle"
  if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "SwiftPM resource bundle is missing: $RESOURCE_BUNDLE" >&2
    exit 1
  fi
  ditto "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/$RESOURCE_NAME.bundle"
done
for LOCALIZATION_DIR in "$PROJECT_DIR"/Support/*.lproj; do
  [[ -d "$LOCALIZATION_DIR" ]] || continue
  ditto "$LOCALIZATION_DIR" "$APP_DIR/Contents/Resources/$(basename "$LOCALIZATION_DIR")"
done
swift scripts/make-icon.swift "$PROJECT_DIR/work/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/work/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
xattr -cr "$APP_DIR"
SIGN_ARGUMENTS=(--force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID")
if [[ "$MODE" == "production" ]]; then
  SIGN_ARGUMENTS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGUMENTS[@]}" "$APP_DIR"
codesign --verify --strict "$APP_DIR"

notarize() {
  local artifact="$1" report="$2" status
  xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$report"
  status="$(plutil -extract status raw -o - "$report")"
  if [[ "$status" != "Accepted" ]]; then
    cat "$report" >&2
    echo "Apple did not accept the notarization submission." >&2
    exit 1
  fi
}

if [[ "$MODE" == "production" ]]; then
  SIGN_DETAILS="$(codesign --display --verbose=4 "$APP_DIR" 2>&1)"
  if [[ "$SIGN_DETAILS" != *"Authority=Developer ID Application:"* ]]; then
    echo "Production requires a Developer ID Application signature." >&2
    exit 1
  fi
  # Xcode 27's lipo treats a second architecture after -verify_arch as another input file.
  for arch in arm64 x86_64; do
    lipo "$APP_DIR/Contents/MacOS/SnapPile" -verify_arch "$arch"
  done
  ditto -c -k --norsrc --noextattr --keepParent "$APP_DIR" "$STAGING_DIR/notarize.zip"
  echo "Submitting the app to Apple for notarization …"
  notarize "$STAGING_DIR/notarize.zip" "$OUTPUT_DIR/notarization-app.json"
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
  spctl --assess --type execute --verbose=2 "$APP_DIR"
fi

# This destination is generated by this script and contains no user data.
rm -rf "$OUTPUT_APP"
ditto --norsrc --noextattr "$APP_DIR" "$OUTPUT_APP"
ditto -c -k --norsrc --noextattr --keepParent "$APP_DIR" "$OUTPUT_DIR/SnapPile-macOS.zip"
if [[ "$MODE" == "production" ]]; then
  # Verify the exact download after extraction, including the stapled ticket.
  ditto -x -k "$OUTPUT_DIR/SnapPile-macOS.zip" "$STAGING_DIR/zip-check"
  for verify_app in "$OUTPUT_APP" "$STAGING_DIR/zip-check/SnapPile.app"; do
    codesign --verify --deep --strict "$verify_app"
    xcrun stapler validate "$verify_app"
    spctl --assess --type execute --verbose=2 "$verify_app"
  done
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)"
  DMG_PATH="$OUTPUT_DIR/SnapPile-$VERSION.dmg"
  mkdir -p "$STAGING_DIR/dmg"
  ditto --norsrc --noextattr "$APP_DIR" "$STAGING_DIR/dmg/SnapPile.app"
  ln -s /Applications "$STAGING_DIR/dmg/Applications"
  hdiutil create -volname "SnapPile $VERSION" -srcfolder "$STAGING_DIR/dmg" -ov -format UDZO "$DMG_PATH"
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
  echo "Submitting the DMG to Apple for notarization …"
  notarize "$DMG_PATH" "$OUTPUT_DIR/notarization-dmg.json"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  codesign --verify --strict "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
  echo "Notarized universal DMG: $DMG_PATH"
fi
echo "App created: $OUTPUT_APP"
echo "Verified app archive: $OUTPUT_DIR/SnapPile-macOS.zip"
