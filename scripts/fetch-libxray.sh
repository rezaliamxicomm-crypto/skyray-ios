#!/usr/bin/env bash
# Fetches the libXray release pinned in Vendor/libxray.lock and puts LibXray.xcframework where the
# SkyRayXray package expects it. Verifies the zip's sha256. Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=$(sed -n 's/^tag=//p' Vendor/libxray.lock); ASSET=$(sed -n 's/^asset=//p' Vendor/libxray.lock); SHA=$(sed -n 's/^sha256=//p' Vendor/libxray.lock)
DEST=Packages/SkyRayXray/Vendor
if [ -f "$DEST/LibXray.xcframework/Info.plist" ] && [ "$(cat "$DEST/.tag" 2>/dev/null || true)" = "$TAG" ]; then
  echo "LibXray $TAG already in place"; exit 0
fi
mkdir -p "$DEST" build
ZIP="build/libxray-$TAG-$ASSET"
[ -f "$ZIP" ] || curl -fsSL -o "$ZIP" "https://github.com/XTLS/libXray/releases/download/$TAG/$ASSET"
echo "$SHA  $ZIP" | shasum -a 256 -c -
rm -rf "$DEST/LibXray.xcframework" build/libxray-unzip
mkdir -p build/libxray-unzip
unzip -q "$ZIP" -d build/libxray-unzip
mv build/libxray-unzip/libxray-apple-cgo/LibXray.xcframework "$DEST/"
echo "$TAG" > "$DEST/.tag"
echo "LibXray $TAG -> $DEST/LibXray.xcframework"
