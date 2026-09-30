#!/usr/bin/env bash
# Builds HevSocks5Tunnel.xcframework (iPhone arm64 + simulator arm64) from the hev-socks5-tunnel source release
# pinned in Vendor/hev.lock (sha256 verified) into Packages/SkyRayHev/Vendor/. The same recipe as upstream's
# build-apple.sh, minus the macOS and tvOS slices. Needs Xcode. Idempotent: a matching .tag skips the build.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=$(sed -n 's/^tag=//p' Vendor/hev.lock); ASSET=$(sed -n 's/^asset=//p' Vendor/hev.lock); SHA=$(sed -n 's/^sha256=//p' Vendor/hev.lock)
DEST=Packages/SkyRayHev/Vendor
if [ -f "$DEST/HevSocks5Tunnel.xcframework/Info.plist" ] && [ "$(cat "$DEST/.tag" 2>/dev/null || true)" = "$TAG" ]; then
  echo "hev-socks5-tunnel $TAG already in place"; exit 0
fi
mkdir -p "$DEST" build
TARBALL="build/$ASSET"
[ -f "$TARBALL" ] || curl -fsSL -o "$TARBALL" "https://github.com/heiher/hev-socks5-tunnel/releases/download/$TAG/$ASSET"
echo "$SHA  $TARBALL" | shasum -a 256 -c -
rm -rf build/hev-src && mkdir -p build/hev-src
tar -xJf "$TARBALL" -C build/hev-src --strip-components=1
pushd build/hev-src >/dev/null
OUT=apple
rm -rf "$OUT" HevSocks5Tunnel.xcframework; mkdir -p "$OUT/include"
build_static() { # sdk arch min-version-flag
  local sdk=$1 arch=$2 min=$3
  echo "building $sdk $arch"
  make -j"$(sysctl -n hw.ncpu)" PP="xcrun --sdk $sdk clang" CC="xcrun --sdk $sdk clang" \
       CFLAGS="-arch $arch $min" LFLAGS="-arch $arch $min -Wl,-Bsymbolic-functions" static >/dev/null
  mkdir -p "$OUT/$sdk-$arch"
  libtool -static -o "$OUT/$sdk-$arch/libhev-socks5-tunnel.a" \
    bin/libhev-socks5-tunnel.a third-part/lwip/bin/liblwip.a third-part/yaml/bin/libyaml.a third-part/hev-task-system/bin/libhev-task-system.a
  make clean >/dev/null
}
build_static iphoneos arm64 "-mios-version-min=15.0"
build_static iphonesimulator arm64 "-miphonesimulator-version-min=15.0"
# Upstream's header layout, nested under the module's name: Xcode copies every binary target's headers into one
# include/ folder, and LibXray already owns include/module.modulemap there — a flat layout collides with it.
mkdir -p "$OUT/include/HevSocks5Tunnel"
cp src/hev-main.h "$OUT/include/HevSocks5Tunnel/"
cp module.modulemap "$OUT/include/HevSocks5Tunnel/"
xcodebuild -create-xcframework \
  -library "$OUT/iphoneos-arm64/libhev-socks5-tunnel.a" -headers "$OUT/include" \
  -library "$OUT/iphonesimulator-arm64/libhev-socks5-tunnel.a" -headers "$OUT/include" \
  -output HevSocks5Tunnel.xcframework >/dev/null
popd >/dev/null
rm -rf "$DEST/HevSocks5Tunnel.xcframework"
mv build/hev-src/HevSocks5Tunnel.xcframework "$DEST/"
echo "$TAG" > "$DEST/.tag"
echo "hev-socks5-tunnel $TAG -> $DEST/HevSocks5Tunnel.xcframework"
