#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$HOME/Library/Developer/Slate"
SDK=""
for candidate in MacOSX15.5.sdk MacOSX15.4.sdk MacOSX15.2.sdk MacOSX15.sdk; do
    path="/Library/Developer/CommandLineTools/SDKs/$candidate"
    [ -d "$path" ] && SDK="$path" && break
done
[ -z "$SDK" ] && SDK="$(xcrun --show-sdk-path)"

mkdir -p "$BUILD"
SOURCES=()
for file in "$ROOT"/Shared/*.swift "$ROOT"/Sources/*.swift; do
    [ "$(basename "$file")" = "main.swift" ] || SOURCES+=("$file")
done
swiftc -O -sdk "$SDK" -target arm64-apple-macosx14.0 \
    -o "$BUILD/selftest" "${SOURCES[@]}" "$ROOT/Tools/selftest/main.swift"
codesign --force --sign - "$BUILD/selftest"
"$BUILD/selftest"
