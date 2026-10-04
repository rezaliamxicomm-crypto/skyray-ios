#!/usr/bin/env bash
# Builds LibXray.xcframework from XTLS/libXray at the tag pinned in Vendor/libxray-source.lock, with the
# subscription fetch with Encrypted Client Hello compiled into its C bridge: echfetch/echfetch.go and
# echfetch/echfetch_darwin.go as package main, and libxray/echfetch_export.go (CGoFetchSubscriptionEch).
# The build itself is upstream's own recipe (python3 build/main.py apple go), every slice it makes.
# Needs a Mac with Xcode, Go and Python 3. Output: build/libxray-apple-cgo.zip, laid out like upstream's
# release asset. The workflow libxray.yml runs this and publishes the zip; nobody needs to run it by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=$(sed -n 's/^tag=//p' Vendor/libxray-source.lock); COMMIT=$(sed -n 's/^commit=//p' Vendor/libxray-source.lock)
SRC=build/libxray-src
rm -rf "$SRC" build/libxray-apple-cgo build/libxray-apple-cgo.zip
mkdir -p build
git clone -q --depth 1 -b "$TAG" https://github.com/XTLS/libXray "$SRC"
[ "$(git -C "$SRC" rev-parse HEAD)" = "$COMMIT" ] || { echo "libXray $TAG is not commit $COMMIT any more"; exit 1; }
for f in echfetch.go echfetch_darwin.go; do
  sed 's/^package libv2ray$/package main/' "echfetch/$f" > "$SRC/cgo_bridge/$f"
  grep -q '^package main$' "$SRC/cgo_bridge/$f" || { echo "$f: no package clause to rewrite"; exit 1; }
done
cp libxray/echfetch_export.go "$SRC/cgo_bridge/"
(cd "$SRC" && go version && python3 build/main.py apple go)
HEADER="$SRC/LibXray.xcframework/ios-arm64/Headers/libXray.h"
grep -q 'CGoFetchSubscriptionEch' "$HEADER" || { echo "the built header does not export CGoFetchSubscriptionEch"; exit 1; }
grep -q 'CGoInvoke' "$HEADER" || { echo "the built header does not export CGoInvoke"; exit 1; }
mkdir -p build/libxray-apple-cgo
cp -R "$SRC/LibXray.xcframework" build/libxray-apple-cgo/
(cd build && zip -qry libxray-apple-cgo.zip libxray-apple-cgo)
ls "$SRC/LibXray.xcframework"
shasum -a 256 build/libxray-apple-cgo.zip
