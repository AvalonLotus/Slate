#!/bin/bash
set -euo pipefail

# Publishes a version: stamps Info.plist, builds the disk image, and stages it
# on the website repo together with the manifest the app checks.
#
#   scripts/release.sh 1.1
#
# Nothing is committed or pushed — review the website repo, then push it.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Where the download and the manifest are staged. Override for another site:
#   SLATE_SITE=/path/to/site scripts/release.sh 1.1
SITE="${SLATE_SITE:-$HOME/AvalonLotus.com}"
VERSION="${1:-}"

[ -z "$VERSION" ] && { echo "用法：scripts/release.sh <版本>，例如 1.1"; exit 1; }
[ -d "$SITE" ] || { echo "找不到網站 repo：$SITE"; exit 1; }

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
echo "已放進 $SITE/slate/："
ls -lh "$SITE/slate/" | tail -n +2
echo
echo "SHA-256  $SHA"
echo "確認無誤後在網站 repo 提交並推送，App 端即可偵測到 $VERSION。"
