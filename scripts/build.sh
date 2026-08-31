#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Desktop is an iCloud-synced folder; Finder xattrs there break code signing.
BUILD="$HOME/Library/Developer/Slate"
BINARY_NAME="Slate"
TARGET="arm64-apple-macosx14.0"

APP="$BUILD/Slate.app"
BUNDLE_ID="com.avalonlotus.slate"

SDK=""
for candidate in MacOSX15.5.sdk MacOSX15.4.sdk MacOSX15.2.sdk MacOSX15.sdk; do
    path="/Library/Developer/CommandLineTools/SDKs/$candidate"
    [ -d "$path" ] && SDK="$path" && break
done
[ -z "$SDK" ] && SDK="$(xcrun --show-sdk-path)"
echo "SDK: $SDK"

pkill -x "$BINARY_NAME" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling app"
swiftc -O -sdk "$SDK" -target "$TARGET" \
    -framework AppKit -framework SwiftUI -framework LocalAuthentication \
    -o "$APP/Contents/MacOS/$BINARY_NAME" \
    "$ROOT"/Shared/*.swift "$ROOT"/Sources/*.swift

echo "Rendering icon"
MARKS="$BUILD/marks"
swiftc -O -sdk "$SDK" -target "$TARGET" -o "$BUILD/icon-lab" "$ROOT/Tools/icon-lab/main.swift"
"$BUILD/icon-lab" "$MARKS" q >/dev/null
SOURCE_ICON="$MARKS/SLATE.png"
[ -f "$SOURCE_ICON" ] || { echo "icon-lab did not produce SLATE.png"; exit 1; }

ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for entry in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
             "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
             "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
    set -- $entry
    sips -z "$1" "$1" "$SOURCE_ICON" --out "$ICONSET/$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "Compiling slate command line tool"
mkdir -p "$BUILD/bin"
CLI_SOURCES=()
for file in "$ROOT"/Shared/*.swift "$ROOT"/Sources/*.swift; do
    [ "$(basename "$file")" = "main.swift" ] || CLI_SOURCES+=("$file")
done
swiftc -O -sdk "$SDK" -target "$TARGET" \
    -framework AppKit -framework SwiftUI -framework LocalAuthentication \
    -o "$BUILD/bin/slate" "${CLI_SOURCES[@]}" "$ROOT/Tools/cli/main.swift"
codesign --force --sign - "$BUILD/bin/slate"

sed "s|com.avalonlotus.slate|$BUNDLE_ID|" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
# The build number is the minute this binary was produced, so two builds of the
# same marketing version are still told apart.
BUILD_STAMP="$(date +%Y%m%d%H%M)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_STAMP" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

xattr -cr "$APP"
echo "Signing"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=1 "$APP"

echo "Built: $APP (build $BUILD_STAMP)"

# Running from /Applications is the normal case, so a fresh build replaces the
# installed copy instead of waiting to be dragged out of the disk image again.
INSTALLED="/Applications/$(basename "$APP")"
if [ -d "$INSTALLED" ]; then
    rm -rf "$INSTALLED"
    ditto "$APP" "$INSTALLED"
    echo "Installed: $INSTALLED"
fi
