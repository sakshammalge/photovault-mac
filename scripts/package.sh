#!/usr/bin/env bash
# Builds PhotoVault.app (universal, ad-hoc signed) plus a .dmg and .zip into dist/.
# Usage: scripts/package.sh [--arm64-only]
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=PhotoVault
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)
DIST=dist
APP="$DIST/$NAME.app"

ARCHS=(arm64 x86_64)
[[ "${1:-}" == "--arm64-only" ]] && ARCHS=(arm64)

# Build each architecture separately and merge with lipo; this works with just the
# Command Line Tools (a multi-arch `swift build --arch` needs full Xcode).
echo "==> Building $NAME $VERSION (release: ${ARCHS[*]})"
BINS=()
for arch in "${ARCHS[@]}"; do
  swift build -c release --triple "$arch-apple-macosx13.0"
  BINS+=("$(swift build -c release --triple "$arch-apple-macosx13.0" --show-bin-path)/$NAME")
done
mkdir -p "$DIST"
BIN="$DIST/$NAME.bin"
lipo -create "${BINS[@]}" -output "$BIN"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$BIN" "$APP/Contents/MacOS/$NAME"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - --options runtime \
  --entitlements Support/PhotoVault.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Packaging"
ZIP="$DIST/$NAME-$VERSION.zip"
DMG="$DIST/$NAME-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
(cd "$DIST" && shasum -a 256 "$NAME-$VERSION.zip" "$NAME-$VERSION.dmg" > SHA256SUMS.txt)

echo "==> Done"; ls -lh "$DIST"; cat "$DIST/SHA256SUMS.txt"
