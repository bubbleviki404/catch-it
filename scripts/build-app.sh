#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

ARCH_STRING="${CATCHIT_ARCHS:-arm64 x86_64}"
ARCHS=("${(@s: :)ARCH_STRING}")
for ARCH in $ARCHS; do
  swift build -c release --arch "$ARCH" --scratch-path "$ROOT/.build/$ARCH"
done

APP="$ROOT/dist/CatchIt.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ${#ARCHS[@]} -eq 1 ]]; then
  cp "$ROOT/.build/${ARCHS[1]}/release/CatchIt" "$APP/Contents/MacOS/CatchIt"
else
  BINARIES=()
  for ARCH in $ARCHS; do
    BINARIES+=("$ROOT/.build/$ARCH/release/CatchIt")
  done
  lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/CatchIt"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

if [[ -n "${CATCHIT_GITHUB_REPOSITORY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CatchItGitHubRepository $CATCHIT_GITHUB_REPOSITORY" "$APP/Contents/Info.plist"
fi

ICONSET="$ROOT/.build/CatchIt.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -s format png "$ROOT/Resources/AppIcon.svg" --out "$ROOT/.build/AppIcon-1024.png" >/dev/null
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ROOT/.build/AppIcon-1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$ROOT/.build/AppIcon-1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${CATCHIT_CODESIGN_IDENTITY:--}"
if [[ "${CATCHIT_RELEASE:-0}" == "1" ]]; then
  [[ "$IDENTITY" != "-" ]] || { echo "Release build requires CATCHIT_CODESIGN_IDENTITY" >&2; exit 1; }
  [[ -n "${CATCHIT_NOTARY_PROFILE:-}" ]] || { echo "Release build requires CATCHIT_NOTARY_PROFILE" >&2; exit 1; }
  [[ -n "${CATCHIT_GITHUB_REPOSITORY:-}" ]] || { echo "Release build requires CATCHIT_GITHUB_REPOSITORY" >&2; exit 1; }
fi
SIGN_ARGS=(--force --deep --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" \
  --requirements '=designated => identifier "com.gaplab.catchit"' \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ -n "${CATCHIT_NOTARY_PROFILE:-}" && "$IDENTITY" != "-" ]]; then
  ARCHIVE="$ROOT/dist/CatchIt-notarization.zip"
  ditto -c -k --keepParent "$APP" "$ARCHIVE"
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$CATCHIT_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
VERSIONED_ARCHIVE="$ROOT/dist/CatchIt-v$VERSION-universal.zip"
LATEST_ARCHIVE="$ROOT/dist/CatchIt-latest.zip"
ditto -c -k --keepParent "$APP" "$VERSIONED_ARCHIVE"
cp "$VERSIONED_ARCHIVE" "$LATEST_ARCHIVE"

if [[ "${CATCHIT_RELEASE:-0}" == "1" ]]; then
  ARCH_INFO=$(lipo -archs "$APP/Contents/MacOS/CatchIt")
  [[ "$ARCH_INFO" == *arm64* && "$ARCH_INFO" == *x86_64* ]] || { echo "Release binary is not universal: $ARCH_INFO" >&2; exit 1; }
  codesign -dv --verbose=4 "$APP" 2>&1 | rg -q 'flags=.*runtime' || { echo "Hardened Runtime is missing" >&2; exit 1; }
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi

echo "$APP"
