#!/usr/bin/env bash
# Refreshes the lite geo files from Chocolate4U/Iran-v2ray-rules: scripts/fetch-geo.sh <release tag>
# Checks each file against the published .sha256sum, rewrites Vendor/geo/SHA256SUMS and SOURCE. Commit the result.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?release tag, e.g. 202609211010}
for f in geoip-lite.dat geosite-lite.dat; do
  curl -fsSL -o "Vendor/geo/$f" "https://github.com/Chocolate4U/Iran-v2ray-rules/releases/download/$TAG/$f"
  want=$(curl -fsSL "https://github.com/Chocolate4U/Iran-v2ray-rules/releases/download/$TAG/$f.sha256sum" | cut -d' ' -f1)
  have=$(shasum -a 256 "Vendor/geo/$f" | cut -d' ' -f1)
  [ "$want" = "$have" ] || { echo "$f: sha256 mismatch"; exit 1; }
done
(cd Vendor/geo && shasum -a 256 geoip-lite.dat geosite-lite.dat > SHA256SUMS)
echo "Chocolate4U/Iran-v2ray-rules release $TAG (geoip-lite.dat, geosite-lite.dat). Refresh: scripts/fetch-geo.sh <tag>" > Vendor/geo/SOURCE
cat Vendor/geo/SHA256SUMS
