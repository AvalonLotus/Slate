#!/bin/bash
set -euo pipefail

# Builds a drag-to-install disk image: open it, drag Slate onto Applications.
# The volume and the .dmg itself both carry the app's own icon.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$HOME/Library/Developer/Slate"
APP="$BUILD/Slate.app"
ICON="$APP/Contents/Resources/AppIcon.icns"
DMG="$BUILD/Slate.dmg"
STAGE="$BUILD/dmg-stage"
TEMP_DMG="$BUILD/slate-rw.dmg"

"$ROOT/scripts/build.sh" >/dev/null

# A stale mount of the same name would make Finder configure the wrong volume.
for volume in /Volumes/Slate*; do
    [ -d "$volume" ] && hdiutil detach "$volume" -force -quiet 2>/dev/null || true
done

rm -rf "$STAGE" "$DMG" "$TEMP_DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/應用程式"
cp "$ICON" "$STAGE/.VolumeIcon.icns"

# Artwork behind the icons, at both screen densities.
BG="$BUILD/dmg-background"
swiftc -O -sdk "$(xcrun --show-sdk-path)" -o "$BG" "$ROOT/Tools/dmg-background/main.swift"
"$BG" "$BUILD/bg.png" >/dev/null
mkdir -p "$STAGE/.background"
tiffutil -cathidpicheck "$BUILD/bg.png" "$BUILD/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null
rm -f "$BUILD/bg.png" "$BUILD/bg@2x.png" "$BG"

# Writable first, so the volume can be flagged as having a custom icon.
hdiutil create -volname "Slate" -srcfolder "$STAGE" -ov -format UDRW "$TEMP_DMG" >/dev/null
MOUNT=$(hdiutil attach "$TEMP_DMG" -nobrowse -noverify | grep -o '/Volumes/.*' | head -1)
SetFile -a C "$MOUNT"

# Lay the window out like an installer: app on the left, Applications on the
# right. Needs Finder automation; skipped silently when that is not granted.
osascript >/dev/null 2>&1 <<APPLESCRIPT || echo "（Finder 版面設定略過：未取得自動化權限）"
tell application "Finder"
    tell disk "Slate"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 150, 840, 578}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.tiff"
        set position of item "Slate.app" of container window to {160, 190}
        set position of item "應用程式" of container window to {480, 190}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT" -quiet
hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG" >/dev/null

# And give the .dmg file itself the same icon in Finder.
WORK="$BUILD/icon-work"
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$ICON" "$WORK/icon.icns"
sips -i "$WORK/icon.icns" >/dev/null
DeRez -only icns "$WORK/icon.icns" > "$WORK/icon.rsrc"
Rez -append "$WORK/icon.rsrc" -o "$DMG"
SetFile -a C "$DMG"

rm -rf "$STAGE" "$TEMP_DMG" "$WORK"
echo "$DMG"
