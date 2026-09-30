#!/usr/bin/env bash
# Refreshes the lite geo files from Chocolate4U/Iran-v2ray-rules: scripts/fetch-geo.sh <release tag>
# Downloads geoip-lite.dat / geosite-lite.dat, checks each against the published .sha256sum, stores them under the
# names Xray looks up (geoip.dat, geosite.dat), rewrites Vendor/geo/SHA256SUMS and SOURCE. Commit the result.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?release tag, e.g. 202609211010}
for pair in geoip-lite.dat:geoip.dat geosite-lite.dat:geosite.dat; do
  src=${pair%%:*}; dst=${pair#*:}
  curl -fsSL -o "Vendor/geo/$dst" "https://github.com/Chocolate4U/Iran-v2ray-rules/releases/download/$TAG/$src"
  want=$(curl -fsSL "https://github.com/Chocolate4U/Iran-v2ray-rules/releases/download/$TAG/$src.sha256sum" | cut -d' ' -f1)
  have=$(shasum -a 256 "Vendor/geo/$dst" | cut -d' ' -f1)
  [ "$want" = "$have" ] || { echo "$src: sha256 mismatch"; exit 1; }
done
(cd Vendor/geo && shasum -a 256 geoip.dat geosite.dat > SHA256SUMS)
printf 'Chocolate4U/Iran-v2ray-rules release %s: its geoip-lite.dat and geosite-lite.dat, stored under the names Xray\nlooks up (geoip.dat, geosite.dat) in XRAY_LOCATION_ASSET. Refresh: scripts/fetch-geo.sh <tag>\n' "$TAG" > Vendor/geo/SOURCE
cat Vendor/geo/SHA256SUMS
