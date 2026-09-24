#!/bin/bash
set -euo pipefail

# Builds a version: stamps Info.plist, builds the disk image, and puts it in a
# local release folder together with the update manifest. Nothing is copied to
# the website.
#
#   scripts/release.sh 1.1
#
# Nothing is committed, pushed or published.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Where the disk image, the zip and the manifest are written. Override with:
#   SLATE_SITE=/path/to/folder scripts/release.sh 1.1
SITE="${SLATE_SITE:-$HOME/Library/Developer/Slate/release}"
VERSION="${1:-}"

[ -z "$VERSION" ] && { echo "用法：scripts/release.sh <版本>，例如 1.1"; exit 1; }
mkdir -p "$SITE"

PLIST="$ROOT/Resources/Info.plist"
# The build number is stamped by build.sh at compile time.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
echo "版本標記為 $VERSION"

"$ROOT/scripts/package.sh"

mkdir -p "$SITE/slate"
cp "$HOME/Library/Developer/Slate/Slate.dmg" "$SITE/slate/Slate-$VERSION.dmg"
cp "$HOME/Library/Developer/Slate/Slate.dmg" "$SITE/slate/Slate.dmg"

# The zip is what the in-app updater downloads: no volume to mount, and ditto
# keeps the signature intact on both ends.
ZIP="$SITE/slate/Slate-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$HOME/Library/Developer/Slate/Slate.app" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

cat > "$SITE/slate/latest.json" <<JSON
{
  "version": "$VERSION",
  "url": "https://avalonlotus.com/slate/Slate-$VERSION.dmg",
  "zip": "https://avalonlotus.com/slate/Slate-$VERSION.zip",
  "sha256": "$SHA"
}
JSON

echo
echo "已存到 $SITE/slate/（沒有放到官網）："
ls -lh "$SITE/slate/" | tail -n +2
echo
echo "SHA-256  $SHA"
echo "這些檔案只在這台電腦上，要發布到哪裡由你決定。"
